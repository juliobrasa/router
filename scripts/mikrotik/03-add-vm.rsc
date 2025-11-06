################################################################################
# MikroTik - Add New VM Script
# Descripción: Agregar una nueva VM al routing de WireGuard
#
# IMPORTANTE:
# 1. Edita las variables con los datos de la nueva VM
# 2. Ejecuta: /import 03-add-vm.rsc
################################################################################

# =============================================================================
# VARIABLES - EDITAR CON LOS DATOS DE LA NUEVA VM
# =============================================================================

# IP privada de la nueva VM en Proxmox
:local newVmIP "10.100.0.20"

# Nombre descriptivo de la VM
:local newVmName "new-server"

# Nombre de la interfaz WireGuard
:local wgInterface "wireguard1"

# IP del VPS en el túnel
:local vpsTunnelIP "10.200.0.1"

# =============================================================================
# AGREGAR VM
# =============================================================================

:put "═════════════════════════════════════════════════════════════════"
:put "  Agregando Nueva VM al Routing WireGuard"
:put "═════════════════════════════════════════════════════════════════"
:put ""

:put "[INFO] VM a agregar:"
:put "  IP:     $newVmIP"
:put "  Nombre: $newVmName"
:put ""

# Verificar que la interfaz WireGuard existe
:if ([:len [/interface/wireguard find name=$wgInterface]] = 0) do={
    :put "[ERROR] Interfaz WireGuard '$wgInterface' no encontrada"
    :error "WireGuard not configured"
}

# 1. Agregar regla de NAT Source
:put "[INFO] Agregando regla de NAT Source..."

/ip/firewall/nat add \
    chain=srcnat \
    src-address=$newVmIP \
    out-interface=$wgInterface \
    action=masquerade \
    comment="WireGuard: SRCNAT for $newVmName ($newVmIP)"

:put "[OK] Regla NAT agregada"
:put ""

# 2. Agregar marca de routing
:put "[INFO] Agregando marca de routing..."

/ip/firewall/mangle add \
    chain=prerouting \
    src-address=$newVmIP \
    action=mark-routing \
    new-routing-mark=via-wireguard \
    passthrough=yes \
    comment="WireGuard: Mark routing for $newVmName ($newVmIP)"

:put "[OK] Marca de routing agregada"
:put ""

# 3. Verificar
:put "═════════════════════════════════════════════════════════════════"
:put "  VERIFICACIÓN"
:put "═════════════════════════════════════════════════════════════════"
:put ""

:put "[INFO] Reglas NAT para $newVmIP:"
/ip/firewall/nat print where src-address=$newVmIP

:put ""
:put "[INFO] Reglas Mangle para $newVmIP:"
/ip/firewall/mangle print where src-address=$newVmIP

:put ""
:put "═════════════════════════════════════════════════════════════════"
:put "[SUCCESS] ✅ VM agregada exitosamente"
:put "═════════════════════════════════════════════════════════════════"
:put ""
:put "Próximos pasos:"
:put ""
:put "1. En el VPS, agregar mapeo de IP pública:"
:put "   ./03-add-ip-mapping.sh <IP_PUBLICA> $newVmIP $newVmName"
:put ""
:put "2. Configurar la VM en Proxmox:"
:put "   IP: $newVmIP"
:put "   Gateway: (IP del MikroTik en red de Proxmox)"
:put "   DNS: 8.8.8.8, 1.1.1.1"
:put ""
:put "3. Desde la VM, hacer ping al VPS:"
:put "   ping $vpsTunnelIP"
:put ""
:put "4. Verificar IP pública de salida:"
:put "   curl ifconfig.me"
:put ""
