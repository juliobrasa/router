#!/bin/bash
################################################################################
# Test de Conectividad - Sistema WireGuard
# Ejecutar desde el VPS después de completar toda la configuración
################################################################################

# Colores
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "═══════════════════════════════════════════════════════════════"
echo "  Test de Conectividad - WireGuard Tunnel System"
echo "═══════════════════════════════════════════════════════════════"
echo ""

# Cargar configuración
if [ -f "../config/variables.env" ]; then
    source ../config/variables.env
elif [ -f "/root/wireguard-setup/variables.env" ]; then
    source /root/wireguard-setup/variables.env
fi

ERRORS=0
WARNINGS=0

# Test 1: WireGuard está corriendo
echo -n "✓ Test 1: WireGuard service activo... "
if systemctl is-active --quiet wg-quick@wg0; then
    echo -e "${GREEN}OK${NC}"
else
    echo -e "${RED}FAIL${NC}"
    ((ERRORS++))
fi

# Test 2: Interfaz wg0 existe
echo -n "✓ Test 2: Interfaz wg0 existe... "
if ip link show wg0 > /dev/null 2>&1; then
    echo -e "${GREEN}OK${NC}"
else
    echo -e "${RED}FAIL${NC}"
    ((ERRORS++))
fi

# Test 3: IP forwarding habilitado
echo -n "✓ Test 3: IP forwarding habilitado... "
if sysctl net.ipv4.ip_forward | grep -q "= 1"; then
    echo -e "${GREEN}OK${NC}"
else
    echo -e "${RED}FAIL${NC}"
    ((ERRORS++))
fi

# Test 4: Peer conectado
echo -n "✓ Test 4: Peer MikroTik conectado... "
if wg show wg0 | grep -q "latest handshake"; then
    HANDSHAKE=$(wg show wg0 latest-handshakes | awk '{print $2}')
    if [ "$HANDSHAKE" -lt 120 ]; then
        echo -e "${GREEN}OK${NC} (${HANDSHAKE}s ago)"
    else
        echo -e "${YELLOW}WARNING${NC} (${HANDSHAKE}s ago - puede estar desconectado)"
        ((WARNINGS++))
    fi
else
    echo -e "${RED}FAIL${NC} (nunca conectó)"
    ((ERRORS++))
fi

# Test 5: Ping a MikroTik
echo -n "✓ Test 5: Ping a MikroTik (10.200.0.2)... "
if ping -c 3 -W 3 10.200.0.2 > /dev/null 2>&1; then
    echo -e "${GREEN}OK${NC}"
else
    echo -e "${RED}FAIL${NC}"
    ((ERRORS++))
fi

# Test 6: Reglas NAT configuradas
echo -n "✓ Test 6: Reglas NAT DNAT configuradas... "
DNAT_COUNT=$(iptables -t nat -L PREROUTING -n | grep -c "DNAT")
if [ "$DNAT_COUNT" -gt 0 ]; then
    echo -e "${GREEN}OK${NC} ($DNAT_COUNT reglas)"
else
    echo -e "${RED}FAIL${NC}"
    ((ERRORS++))
fi

echo -n "✓ Test 7: Reglas NAT SNAT configuradas... "
SNAT_COUNT=$(iptables -t nat -L POSTROUTING -n | grep -c "SNAT")
if [ "$SNAT_COUNT" -gt 0 ]; then
    echo -e "${GREEN}OK${NC} ($SNAT_COUNT reglas)"
else
    echo -e "${RED}FAIL${NC}"
    ((ERRORS++))
fi

# Test 8: IPs adicionales asignadas
if [ -n "$VPS_INTERFACE" ] && [ ${#VPS_ADDITIONAL_IPS[@]} -gt 0 ]; then
    echo -n "✓ Test 8: IPs adicionales asignadas... "
    ASSIGNED=0
    for ip in "${VPS_ADDITIONAL_IPS[@]}"; do
        if ip addr show $VPS_INTERFACE | grep -q "$ip"; then
            ((ASSIGNED++))
        fi
    done
    if [ "$ASSIGNED" -eq ${#VPS_ADDITIONAL_IPS[@]} ]; then
        echo -e "${GREEN}OK${NC} ($ASSIGNED/${#VPS_ADDITIONAL_IPS[@]})"
    else
        echo -e "${YELLOW}WARNING${NC} ($ASSIGNED/${#VPS_ADDITIONAL_IPS[@]} asignadas)"
        ((WARNINGS++))
    fi
fi

# Test 9: Puerto WireGuard escuchando
echo -n "✓ Test 9: Puerto 51820 escuchando... "
if netstat -ulnp 2>/dev/null | grep -q ":51820"; then
    echo -e "${GREEN}OK${NC}"
else
    echo -e "${RED}FAIL${NC}"
    ((ERRORS++))
fi

# Test 10: Sin errores en logs recientes
echo -n "✓ Test 10: Logs sin errores (últimos 5 min)... "
ERROR_COUNT=$(journalctl -u wg-quick@wg0 --since "5 minutes ago" -p err --no-pager 2>/dev/null | wc -l)
if [ "$ERROR_COUNT" -eq 0 ]; then
    echo -e "${GREEN}OK${NC}"
else
    echo -e "${YELLOW}WARNING${NC} ($ERROR_COUNT errores)"
    ((WARNINGS++))
fi

echo ""
echo "═══════════════════════════════════════════════════════════════"

# Resumen
if [ "$ERRORS" -eq 0 ] && [ "$WARNINGS" -eq 0 ]; then
    echo -e "${GREEN}✅ TODOS LOS TESTS PASARON${NC}"
    echo ""
    echo "El sistema WireGuard está configurado correctamente."
    echo ""
    echo "Próximos pasos:"
    echo "  1. Configurar VMs en Proxmox"
    echo "  2. Desde cada VM, ejecutar: curl ifconfig.me"
    echo "  3. Verificar que muestra la IP pública asignada"
    EXIT_CODE=0
elif [ "$ERRORS" -eq 0 ]; then
    echo -e "${YELLOW}⚠️  TESTS PASARON CON ADVERTENCIAS${NC}"
    echo ""
    echo "Warnings: $WARNINGS"
    echo "El sistema funciona pero hay algunas advertencias."
    EXIT_CODE=0
else
    echo -e "${RED}❌ ALGUNOS TESTS FALLARON${NC}"
    echo ""
    echo "Errores: $ERRORS"
    echo "Warnings: $WARNINGS"
    echo ""
    echo "Revisar documentación de troubleshooting:"
    echo "  docs/troubleshooting.md"
    EXIT_CODE=1
fi

echo "═══════════════════════════════════════════════════════════════"

exit $EXIT_CODE
