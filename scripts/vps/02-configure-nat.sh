#!/bin/bash
################################################################################
# Script: 02-configure-nat.sh
# Descripción: Configuración de NAT 1:1 para mapear IPs públicas a VMs
# Uso: ./02-configure-nat.sh
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
    exit 1
fi

log_info "Cargando configuración desde: $CONFIG_FILE"
source "$CONFIG_FILE"

# Validar configuración
if ! _validate_config; then
    log_error "Configuración inválida"
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
}

check_wireguard() {
    if ! systemctl is-active --quiet wg-quick@wg0; then
        log_error "WireGuard no está corriendo"
        log_info "Ejecuta primero: ./01-setup-wireguard.sh"
        exit 1
    fi
    log_success "WireGuard está corriendo"
}

# =============================================================================
# ASIGNAR IPS ADICIONALES A LA INTERFAZ
# =============================================================================

assign_additional_ips() {
    separator
    log_info "Asignando IPs públicas adicionales a la interfaz $VPS_INTERFACE..."

    local count=0
    for public_ip in "${VPS_ADDITIONAL_IPS[@]}"; do
        log_info "Verificando IP: $public_ip"

        # Verificar si la IP ya está asignada
        if ip addr show $VPS_INTERFACE | grep -q "$public_ip"; then
            log_warning "  IP $public_ip ya está asignada"
        else
            # Asignar IP a la interfaz
            log_info "  Asignando $public_ip a $VPS_INTERFACE..."
            ip addr add $public_ip/32 dev $VPS_INTERFACE

            log_success "  IP $public_ip asignada"
        fi

        ((count++))
    done

    log_success "$count IPs públicas verificadas/asignadas"

    # Hacer permanente agregando a /etc/network/interfaces o netplan
    make_ips_persistent
}

make_ips_persistent() {
    log_info "Haciendo IPs permanentes..."

    # Crear script de post-up
    cat > /etc/network/if-up.d/assign-additional-ips <<'EOF'
#!/bin/bash
# Script para asignar IPs adicionales al iniciar la interfaz
# Generado automáticamente

EOF

    # Cargar variables
    echo "source /root/wireguard-setup/variables.env" >> /etc/network/if-up.d/assign-additional-ips

    # Agregar comandos de asignación
    cat >> /etc/network/if-up.d/assign-additional-ips <<'EOF'

for public_ip in "${VPS_ADDITIONAL_IPS[@]}"; do
    # Verificar si ya está asignada
    if ! ip addr show $VPS_INTERFACE | grep -q "$public_ip"; then
        ip addr add $public_ip/32 dev $VPS_INTERFACE
    fi
done
EOF

    chmod +x /etc/network/if-up.d/assign-additional-ips
    log_success "IPs adicionales se asignarán automáticamente al reiniciar"
}

# =============================================================================
# CONFIGURAR NAT 1:1
# =============================================================================

configure_nat_1to1() {
    separator
    log_info "Configurando NAT 1:1 (mapeo IP pública → VM privada)..."

    # Verificar que hay la misma cantidad de IPs públicas y privadas
    if [ ${#VPS_ADDITIONAL_IPS[@]} -ne ${#VM_IPS[@]} ]; then
        log_error "Cantidad de IPs públicas y privadas no coincide"
        log_error "IPs públicas: ${#VPS_ADDITIONAL_IPS[@]}"
        log_error "IPs privadas: ${#VM_IPS[@]}"
        exit 1
    fi

    # Crear archivo de reglas NAT
    NAT_RULES_FILE="/etc/wireguard/nat-rules.txt"
    echo "# NAT 1:1 Rules - Generated $(date)" > $NAT_RULES_FILE
    echo "# Format: PUBLIC_IP:VM_PRIVATE_IP" >> $NAT_RULES_FILE
    echo "" >> $NAT_RULES_FILE

    # Limpiar reglas NAT existentes de WireGuard (si existen)
    log_info "Limpiando reglas NAT anteriores..."
    iptables -t nat -S | grep "10.100.0" | sed 's/-A //' | while read rule; do
        iptables -t nat -D $rule 2>/dev/null || true
    done

    # Crear reglas NAT 1:1
    local count=0
    for i in "${!VPS_ADDITIONAL_IPS[@]}"; do
        public_ip="${VPS_ADDITIONAL_IPS[$i]}"
        vm_ip="${VM_IPS[$i]}"
        vm_name=""

        # Obtener nombre de VM si existe
        if [ $i -lt ${#VM_NAMES[@]} ]; then
            vm_name=" (${VM_NAMES[$i]})"
        fi

        log_info "Configurando: $public_ip → $vm_ip$vm_name"

        # DNAT: Tráfico entrante a IP pública → VM privada
        iptables -t nat -A PREROUTING -d $public_ip -j DNAT --to-destination $vm_ip

        # SNAT: Tráfico saliente de VM → IP pública
        iptables -t nat -A POSTROUTING -s $vm_ip -o $VPS_INTERFACE -j SNAT --to-source $public_ip

        # Guardar en archivo
        echo "$public_ip:$vm_ip$vm_name" >> $NAT_RULES_FILE

        log_success "  ✓ Regla NAT creada: $public_ip ↔ $vm_ip"

        ((count++))
    done

    log_success "$count reglas NAT 1:1 configuradas"
}

# =============================================================================
# GUARDAR REGLAS DE FIREWALL
# =============================================================================

save_iptables_rules() {
    separator
    log_info "Guardando reglas de iptables..."

    # Guardar reglas IPv4
    if command -v netfilter-persistent &> /dev/null; then
        netfilter-persistent save
        log_success "Reglas guardadas con netfilter-persistent"
    elif command -v iptables-save &> /dev/null; then
        iptables-save > /etc/iptables/rules.v4
        log_success "Reglas guardadas en /etc/iptables/rules.v4"
    else
        log_warning "No se pudo guardar las reglas automáticamente"
        log_info "Las reglas se aplicarán en cada reinicio mediante scripts"
    fi

    # Crear script de restauración
    create_restore_script
}

create_restore_script() {
    log_info "Creando script de restauración de reglas NAT..."

    cat > /etc/wireguard/restore-nat.sh <<'EOFSCRIPT'
#!/bin/bash
################################################################################
# Script de Restauración de Reglas NAT
# Generado automáticamente
# Ejecuta este script después de reiniciar si las reglas NAT no se cargan
################################################################################

# Cargar variables
if [ -f /root/wireguard-setup/variables.env ]; then
    source /root/wireguard-setup/variables.env
else
    echo "Error: No se encuentra variables.env"
    exit 1
fi

echo "Restaurando reglas NAT 1:1..."

# Limpiar reglas antiguas
iptables -t nat -F PREROUTING
iptables -t nat -F POSTROUTING

# Aplicar reglas NAT 1:1
for i in "${!VPS_ADDITIONAL_IPS[@]}"; do
    public_ip="${VPS_ADDITIONAL_IPS[$i]}"
    vm_ip="${VM_IPS[$i]}"

    # DNAT: Entrante
    iptables -t nat -A PREROUTING -d $public_ip -j DNAT --to-destination $vm_ip

    # SNAT: Saliente
    iptables -t nat -A POSTROUTING -s $vm_ip -o $VPS_INTERFACE -j SNAT --to-source $public_ip

    echo "  ✓ $public_ip ↔ $vm_ip"
done

echo "Reglas NAT restauradas correctamente"

# Guardar reglas
if command -v netfilter-persistent &> /dev/null; then
    netfilter-persistent save
elif [ -d /etc/iptables ]; then
    iptables-save > /etc/iptables/rules.v4
fi

EOFSCRIPT

    chmod +x /etc/wireguard/restore-nat.sh
    log_success "Script de restauración creado: /etc/wireguard/restore-nat.sh"
}

# =============================================================================
# VERIFICACIÓN
# =============================================================================

verify_nat_configuration() {
    separator
    log_info "Verificando configuración NAT..."
    echo ""

    # Mostrar tabla NAT
    log_info "Tabla NAT - PREROUTING (tráfico entrante):"
    iptables -t nat -L PREROUTING -n -v --line-numbers | grep -E "(Chain|10.100)" || echo "  (sin reglas)"

    echo ""
    log_info "Tabla NAT - POSTROUTING (tráfico saliente):"
    iptables -t nat -L POSTROUTING -n -v --line-numbers | grep -E "(Chain|10.100)" || echo "  (sin reglas)"

    echo ""
    log_info "Resumen de mapeos configurados:"
    echo ""

    if [ -f /etc/wireguard/nat-rules.txt ]; then
        cat /etc/wireguard/nat-rules.txt | grep -v "^#" | grep -v "^$"
    fi

    echo ""
    log_success "Configuración NAT verificada"
}

# =============================================================================
# MOSTRAR INFORMACIÓN DE TESTING
# =============================================================================

show_testing_info() {
    separator
    echo ""
    log_info "INFORMACIÓN PARA TESTING:"
    echo ""
    echo "═══════════════════════════════════════════════════════════════════════"
    echo "Verificar NAT desde el VPS:"
    echo "═══════════════════════════════════════════════════════════════════════"
    echo ""
    echo "1. Ver reglas NAT activas:"
    echo "   iptables -t nat -L -n -v"
    echo ""
    echo "2. Ver tráfico en tiempo real:"
    echo "   watch -n1 'iptables -t nat -L -n -v | grep 10.100'"
    echo ""
    echo "3. Tcpdump para debug:"
    echo "   tcpdump -i wg0 -n"
    echo ""
    echo "═══════════════════════════════════════════════════════════════════════"
    echo "Testing desde una VM (después de configurar MikroTik):"
    echo "═══════════════════════════════════════════════════════════════════════"
    echo ""
    echo "1. Verificar que la VM puede hacer ping al VPS:"
    echo "   ping $WG_VPS_IP"
    echo ""
    echo "2. Verificar IP pública de salida:"
    echo "   curl ifconfig.me"
    echo "   (Debe mostrar la IP pública asignada a esa VM)"
    echo ""
    echo "3. Traceroute para ver la ruta:"
    echo "   traceroute 8.8.8.8"
    echo ""
    echo "═══════════════════════════════════════════════════════════════════════"
    echo ""
}

# =============================================================================
# SCRIPT PRINCIPAL
# =============================================================================

main() {
    clear
    separator
    echo -e "${BLUE}NAT 1:1 Configuration - VPS${NC}"
    separator
    echo ""

    # Verificaciones
    check_root
    check_wireguard

    # Configuración
    assign_additional_ips
    configure_nat_1to1
    save_iptables_rules

    # Verificación
    verify_nat_configuration

    # Información de testing
    show_testing_info

    separator
    log_success "✅ NAT 1:1 configurado exitosamente"
    echo ""
    log_info "Próximos pasos:"
    echo "  1. Configurar MikroTik: scripts/mikrotik/02-configure-nat.rsc"
    echo "  2. Configurar VMs en Proxmox con IPs estáticas"
    echo "  3. Ejecutar tests de conectividad"
    echo ""
    log_warning "IMPORTANTE: Las reglas NAT están activas"
    log_info "Si necesitas restaurarlas: /etc/wireguard/restore-nat.sh"
    echo ""
    separator
}

# Ejecutar script principal
main

exit 0
