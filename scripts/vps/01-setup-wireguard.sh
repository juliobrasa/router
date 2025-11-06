#!/bin/bash
################################################################################
# Script: 01-setup-wireguard.sh
# Descripción: Instalación y configuración de WireGuard en VPS
# Uso: ./01-setup-wireguard.sh
################################################################################

set -e  # Detener en caso de error

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# =============================================================================
# FUNCIONES AUXILIARES
# =============================================================================

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

log_error() {
    echo -e "${RED}[✗]${NC} $1"
}

separator() {
    echo "════════════════════════════════════════════════════════════════════════════════"
}

# =============================================================================
# CARGAR CONFIGURACIÓN
# =============================================================================

# Buscar archivo de configuración
CONFIG_FILE=""
if [ -f "../../config/variables.env" ]; then
    CONFIG_FILE="../../config/variables.env"
elif [ -f "../config/variables.env" ]; then
    CONFIG_FILE="../config/variables.env"
elif [ -f "/root/wireguard-setup/variables.env" ]; then
    CONFIG_FILE="/root/wireguard-setup/variables.env"
else
    log_error "No se encontró el archivo de configuración variables.env"
    log_info "Copia config/variables.env.example a variables.env y edítalo con tus valores"
    exit 1
fi

log_info "Cargando configuración desde: $CONFIG_FILE"
source "$CONFIG_FILE"

# Validar configuración
if ! _validate_config; then
    log_error "Configuración inválida. Revisa el archivo $CONFIG_FILE"
    exit 1
fi

log_success "Configuración cargada y validada"

# =============================================================================
# VERIFICACIONES PREVIAS
# =============================================================================

check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "Este script debe ejecutarse como root"
        exit 1
    fi
    log_success "Permisos de root verificados"
}

check_os() {
    log_info "Detectando sistema operativo..."

    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        VERSION=$VERSION_ID
        log_success "Sistema operativo: $OS $VERSION"
    else
        log_error "No se puede detectar el sistema operativo"
        exit 1
    fi

    # Verificar que sea Ubuntu o Debian
    if [[ "$OS" != "ubuntu" && "$OS" != "debian" ]]; then
        log_warning "Este script está optimizado para Ubuntu/Debian"
        log_warning "Puede funcionar en otros sistemas pero no está garantizado"
        read -p "¿Continuar de todas formas? (s/n) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Ss]$ ]]; then
            exit 1
        fi
    fi
}

check_internet() {
    log_info "Verificando conectividad a Internet..."

    if ping -c 1 8.8.8.8 &> /dev/null; then
        log_success "Conectividad a Internet verificada"
    else
        log_error "Sin conectividad a Internet"
        exit 1
    fi
}

# =============================================================================
# INSTALACIÓN DE WIREGUARD
# =============================================================================

install_wireguard() {
    separator
    log_info "Instalando WireGuard..."

    # Actualizar paquetes
    log_info "Actualizando lista de paquetes..."
    apt-get update -qq

    # Instalar WireGuard
    log_info "Instalando paquetes necesarios..."
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
        wireguard \
        wireguard-tools \
        iptables \
        iptables-persistent \
        qrencode \
        net-tools \
        curl \
        > /dev/null 2>&1

    log_success "WireGuard instalado correctamente"
}

# =============================================================================
# GENERACIÓN DE CLAVES
# =============================================================================

generate_keys() {
    separator
    log_info "Generando claves de WireGuard..."

    # Crear directorio para claves
    mkdir -p /etc/wireguard/keys
    chmod 700 /etc/wireguard/keys

    # Generar clave privada del servidor
    if [ ! -f /etc/wireguard/keys/server_private.key ]; then
        wg genkey > /etc/wireguard/keys/server_private.key
        chmod 600 /etc/wireguard/keys/server_private.key
        log_success "Clave privada del servidor generada"
    else
        log_warning "Clave privada del servidor ya existe, reutilizando"
    fi

    # Generar clave pública del servidor
    if [ ! -f /etc/wireguard/keys/server_public.key ]; then
        cat /etc/wireguard/keys/server_private.key | wg pubkey > /etc/wireguard/keys/server_public.key
        log_success "Clave pública del servidor generada"
    else
        log_warning "Clave pública del servidor ya existe, reutilizando"
    fi

    # Generar clave privada del cliente (MikroTik)
    if [ ! -f /etc/wireguard/keys/client_private.key ]; then
        wg genkey > /etc/wireguard/keys/client_private.key
        chmod 600 /etc/wireguard/keys/client_private.key
        log_success "Clave privada del cliente generada"
    else
        log_warning "Clave privada del cliente ya existe, reutilizando"
    fi

    # Generar clave pública del cliente
    if [ ! -f /etc/wireguard/keys/client_public.key ]; then
        cat /etc/wireguard/keys/client_private.key | wg pubkey > /etc/wireguard/keys/client_public.key
        log_success "Clave pública del cliente generada"
    else
        log_warning "Clave pública del cliente ya existe, reutilizando"
    fi

    # Mostrar claves
    separator
    echo ""
    log_info "CLAVES GENERADAS (guárdalas en lugar seguro):"
    echo ""
    echo "═══════════════════════════════════════════════════════════════════════"
    echo "SERVIDOR (VPS):"
    echo "═══════════════════════════════════════════════════════════════════════"
    echo "Private Key:"
    cat /etc/wireguard/keys/server_private.key
    echo ""
    echo "Public Key:"
    cat /etc/wireguard/keys/server_public.key
    echo ""
    echo "═══════════════════════════════════════════════════════════════════════"
    echo "CLIENTE (MikroTik):"
    echo "═══════════════════════════════════════════════════════════════════════"
    echo "Private Key:"
    cat /etc/wireguard/keys/client_private.key
    echo ""
    echo "Public Key:"
    cat /etc/wireguard/keys/client_public.key
    echo ""
    echo "═══════════════════════════════════════════════════════════════════════"
    echo ""
}

# =============================================================================
# CONFIGURACIÓN DE WIREGUARD
# =============================================================================

configure_wireguard() {
    separator
    log_info "Creando configuración de WireGuard..."

    # Leer claves
    SERVER_PRIVATE_KEY=$(cat /etc/wireguard/keys/server_private.key)
    CLIENT_PUBLIC_KEY=$(cat /etc/wireguard/keys/client_public.key)

    # Crear archivo de configuración
    cat > /etc/wireguard/wg0.conf <<EOF
# WireGuard Server Configuration - VPS
# Generado el: $(date)

[Interface]
# Clave privada del servidor
PrivateKey = $SERVER_PRIVATE_KEY

# IP del servidor en el túnel
Address = $WG_VPS_IP/24

# Puerto de escucha
ListenPort = $WG_PORT

# MTU óptimo para evitar fragmentación
MTU = $WG_MTU

# Scripts post-up y post-down para configurar routing
PostUp = iptables -A FORWARD -i wg0 -j ACCEPT
PostUp = iptables -A FORWARD -o wg0 -j ACCEPT
PostUp = iptables -t nat -A POSTROUTING -s $WG_NETWORK -o $VPS_INTERFACE -j MASQUERADE

PostDown = iptables -D FORWARD -i wg0 -j ACCEPT
PostDown = iptables -D FORWARD -o wg0 -j ACCEPT
PostDown = iptables -t nat -D POSTROUTING -s $WG_NETWORK -o $VPS_INTERFACE -j MASQUERADE

[Peer]
# MikroTik (Cliente en oficina)
PublicKey = $CLIENT_PUBLIC_KEY

# IPs permitidas desde el cliente
# Red del túnel + Red de Proxmox
AllowedIPs = $WG_MIKROTIK_IP/32, $PROXMOX_NETWORK

# Endpoint: IP pública de la oficina
# NOTA: El cliente se conectará al servidor, así que esto es opcional
# Endpoint = $OFFICE_PUBLIC_IP:$WG_PORT

# Mantener la conexión viva
PersistentKeepalive = 25
EOF

    chmod 600 /etc/wireguard/wg0.conf
    log_success "Archivo de configuración creado: /etc/wireguard/wg0.conf"
}

# =============================================================================
# HABILITAR IP FORWARDING
# =============================================================================

enable_ip_forwarding() {
    separator
    log_info "Habilitando IP forwarding..."

    # Verificar si ya está habilitado
    if sysctl net.ipv4.ip_forward | grep -q "= 1"; then
        log_warning "IP forwarding ya está habilitado"
    else
        # Habilitar temporalmente
        sysctl -w net.ipv4.ip_forward=1 > /dev/null

        # Habilitar permanentemente
        if grep -q "^net.ipv4.ip_forward=1" /etc/sysctl.conf; then
            log_warning "IP forwarding ya está configurado en /etc/sysctl.conf"
        else
            echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
        fi

        sysctl -p > /dev/null
        log_success "IP forwarding habilitado"
    fi
}

# =============================================================================
# CONFIGURAR FIREWALL
# =============================================================================

configure_firewall() {
    separator
    log_info "Configurando firewall..."

    # Permitir WireGuard
    log_info "Permitiendo puerto UDP $WG_PORT para WireGuard..."
    iptables -A INPUT -p udp --dport $WG_PORT -j ACCEPT

    # Permitir tráfico del túnel
    log_info "Permitiendo tráfico del túnel WireGuard..."
    iptables -A INPUT -i wg0 -j ACCEPT
    iptables -A OUTPUT -o wg0 -j ACCEPT

    # Guardar reglas de firewall
    log_info "Guardando reglas de firewall..."
    if command -v netfilter-persistent &> /dev/null; then
        netfilter-persistent save
    else
        iptables-save > /etc/iptables/rules.v4
    fi

    log_success "Firewall configurado"
}

# =============================================================================
# INICIAR WIREGUARD
# =============================================================================

start_wireguard() {
    separator
    log_info "Iniciando WireGuard..."

    # Habilitar servicio
    systemctl enable wg-quick@wg0 > /dev/null 2>&1

    # Iniciar servicio
    if systemctl is-active --quiet wg-quick@wg0; then
        log_warning "WireGuard ya está corriendo, reiniciando..."
        systemctl restart wg-quick@wg0
    else
        systemctl start wg-quick@wg0
    fi

    # Verificar estado
    if systemctl is-active --quiet wg-quick@wg0; then
        log_success "WireGuard iniciado correctamente"
    else
        log_error "Error al iniciar WireGuard"
        log_info "Verifica los logs con: journalctl -u wg-quick@wg0"
        exit 1
    fi
}

# =============================================================================
# VERIFICACIÓN
# =============================================================================

verify_setup() {
    separator
    log_info "Verificando instalación..."
    echo ""

    # Mostrar estado de WireGuard
    log_info "Estado de WireGuard:"
    wg show

    echo ""
    log_info "Interfaz wg0:"
    ip addr show wg0

    echo ""
    log_success "✓ WireGuard está corriendo correctamente"
}

# =============================================================================
# INFORMACIÓN DE CONFIGURACIÓN PARA MIKROTIK
# =============================================================================

show_mikrotik_info() {
    separator
    echo ""
    log_info "INFORMACIÓN PARA CONFIGURAR MIKROTIK:"
    echo ""

    SERVER_PUBLIC_KEY=$(cat /etc/wireguard/keys/server_public.key)
    CLIENT_PRIVATE_KEY=$(cat /etc/wireguard/keys/client_private.key)

    echo "═══════════════════════════════════════════════════════════════════════"
    echo "Configuración MikroTik"
    echo "═══════════════════════════════════════════════════════════════════════"
    echo ""
    echo "Endpoint (servidor):"
    echo "  IP:   $VPS_PUBLIC_IP"
    echo "  Port: $WG_PORT"
    echo ""
    echo "Public Key del servidor:"
    echo "  $SERVER_PUBLIC_KEY"
    echo ""
    echo "Private Key del cliente (para MikroTik):"
    echo "  $CLIENT_PRIVATE_KEY"
    echo ""
    echo "IPs del túnel:"
    echo "  VPS (servidor):    $WG_VPS_IP"
    echo "  MikroTik (cliente): $WG_MIKROTIK_IP"
    echo ""
    echo "═══════════════════════════════════════════════════════════════════════"
    echo ""
    log_info "Guarda esta información para configurar el MikroTik"
    log_info "O usa el script: scripts/mikrotik/01-setup-wireguard.rsc"
    echo ""
}

# =============================================================================
# SCRIPT PRINCIPAL
# =============================================================================

main() {
    clear
    separator
    echo -e "${BLUE}WireGuard Setup - VPS Configuration${NC}"
    separator
    echo ""

    # Verificaciones previas
    check_root
    check_os
    check_internet

    # Instalación
    install_wireguard

    # Configuración
    generate_keys
    configure_wireguard
    enable_ip_forwarding
    configure_firewall

    # Iniciar servicio
    start_wireguard

    # Verificación
    verify_setup

    # Información para MikroTik
    show_mikrotik_info

    separator
    log_success "✅ WireGuard configurado exitosamente en el VPS"
    echo ""
    log_info "Próximos pasos:"
    echo "  1. Configurar NAT 1:1: ./02-configure-nat.sh"
    echo "  2. Configurar MikroTik: scripts/mikrotik/01-setup-wireguard.rsc"
    echo "  3. Verificar conectividad: ping $WG_MIKROTIK_IP"
    echo ""
    separator
}

# Ejecutar script principal
main

exit 0
