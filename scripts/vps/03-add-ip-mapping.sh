#!/bin/bash
################################################################################
# Script: 03-add-ip-mapping.sh
# Descripción: Agregar un nuevo mapeo IP pública → VM privada
# Uso: ./03-add-ip-mapping.sh <IP_PUBLICA> <IP_VM_PRIVADA> [NOMBRE_VM]
################################################################################

set -e

# Colores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[✓]${NC} $1"; }
log_error() { echo -e "${RED}[✗]${NC} $1"; }

# =============================================================================
# VERIFICAR ARGUMENTOS
# =============================================================================

if [ $# -lt 2 ]; then
    echo "Uso: $0 <IP_PUBLICA> <IP_VM_PRIVADA> [NOMBRE_VM]"
    echo ""
    echo "Ejemplo:"
    echo "  $0 185.123.45.67 10.100.0.20 web-server-3"
    echo ""
    exit 1
fi

PUBLIC_IP="$1"
VM_IP="$2"
VM_NAME="${3:-unnamed}"

# =============================================================================
# CARGAR CONFIGURACIÓN
# =============================================================================

CONFIG_FILE=""
if [ -f "../../config/variables.env" ]; then
    CONFIG_FILE="../../config/variables.env"
elif [ -f "/root/wireguard-setup/variables.env" ]; then
    CONFIG_FILE="/root/wireguard-setup/variables.env"
fi

if [ -n "$CONFIG_FILE" ] && [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
else
    log_error "No se encontró variables.env, usando valores por defecto"
    VPS_INTERFACE="eth0"
fi

# =============================================================================
# VERIFICAR ROOT
# =============================================================================

if [ "$EUID" -ne 0 ]; then
    log_error "Este script debe ejecutarse como root"
    exit 1
fi

# =============================================================================
# AGREGAR IP PÚBLICA
# =============================================================================

log_info "Agregando IP pública $PUBLIC_IP..."

# Verificar si ya está asignada
if ip addr show $VPS_INTERFACE | grep -q "$PUBLIC_IP"; then
    log_info "  IP $PUBLIC_IP ya está asignada a $VPS_INTERFACE"
else
    ip addr add $PUBLIC_IP/32 dev $VPS_INTERFACE
    log_success "  IP $PUBLIC_IP asignada a $VPS_INTERFACE"
fi

# =============================================================================
# CREAR REGLAS NAT
# =============================================================================

log_info "Creando reglas NAT 1:1..."

# DNAT: Tráfico entrante
if iptables -t nat -C PREROUTING -d $PUBLIC_IP -j DNAT --to-destination $VM_IP 2>/dev/null; then
    log_info "  Regla DNAT ya existe"
else
    iptables -t nat -A PREROUTING -d $PUBLIC_IP -j DNAT --to-destination $VM_IP
    log_success "  Regla DNAT creada: $PUBLIC_IP → $VM_IP"
fi

# SNAT: Tráfico saliente
if iptables -t nat -C POSTROUTING -s $VM_IP -o $VPS_INTERFACE -j SNAT --to-source $PUBLIC_IP 2>/dev/null; then
    log_info "  Regla SNAT ya existe"
else
    iptables -t nat -A POSTROUTING -s $VM_IP -o $VPS_INTERFACE -j SNAT --to-source $PUBLIC_IP
    log_success "  Regla SNAT creada: $VM_IP → $PUBLIC_IP"
fi

# =============================================================================
# GUARDAR EN ARCHIVO DE REGLAS
# =============================================================================

NAT_RULES_FILE="/etc/wireguard/nat-rules.txt"
if [ -f "$NAT_RULES_FILE" ]; then
    # Verificar si ya existe
    if grep -q "$PUBLIC_IP:$VM_IP" "$NAT_RULES_FILE"; then
        log_info "Mapeo ya existe en $NAT_RULES_FILE"
    else
        echo "$PUBLIC_IP:$VM_IP ($VM_NAME)" >> "$NAT_RULES_FILE"
        log_success "Mapeo guardado en $NAT_RULES_FILE"
    fi
fi

# =============================================================================
# GUARDAR REGLAS
# =============================================================================

log_info "Guardando reglas de iptables..."

if command -v netfilter-persistent &> /dev/null; then
    netfilter-persistent save
elif [ -d /etc/iptables ]; then
    iptables-save > /etc/iptables/rules.v4
fi

log_success "Reglas guardadas"

# =============================================================================
# MOSTRAR RESULTADO
# =============================================================================

echo ""
echo "═══════════════════════════════════════════════════════════════════════"
log_success "✅ Mapeo NAT 1:1 agregado exitosamente"
echo "═══════════════════════════════════════════════════════════════════════"
echo ""
echo "  IP Pública:   $PUBLIC_IP"
echo "  IP VM:        $VM_IP"
echo "  Nombre VM:    $VM_NAME"
echo ""
echo "Verificar mapeo:"
echo "  iptables -t nat -L -n -v | grep $PUBLIC_IP"
echo ""
echo "Testing desde la VM:"
echo "  curl ifconfig.me"
echo "  (Debe mostrar: $PUBLIC_IP)"
echo ""
echo "═══════════════════════════════════════════════════════════════════════"
echo ""

exit 0
