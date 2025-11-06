################################################################################
# MikroTik WireGuard Configuration Script
# Descripción: Configuración inicial de WireGuard en MikroTik RouterOS 7.x
#
# IMPORTANTE:
# 1. Edita las variables al principio del script con tus valores
# 2. Ejecuta desde terminal o importa: /import 01-setup-wireguard.rsc
# 3. Requiere RouterOS 7.x o superior (WireGuard nativo)
################################################################################

# =============================================================================
# VARIABLES DE CONFIGURACIÓN - EDITAR ESTAS LÍNEAS
# =============================================================================

# IP pública del VPS (endpoint del servidor WireGuard)
:local vpsPublicIP "X.X.X.X"

# Puerto WireGuard del servidor
:local wgPort 51820

# Clave privada del cliente MikroTik
# Obtener del output del script VPS: /etc/wireguard/keys/client_private.key
:local clientPrivateKey "PASTE_CLIENT_PRIVATE_KEY_HERE"

# Clave pública del servidor VPS
# Obtener del output del script VPS: /etc/wireguard/keys/server_public.key
:local serverPublicKey "PASTE_SERVER_PUBLIC_KEY_HERE"

# IPs del túnel WireGuard
:local mikrotikTunnelIP "10.200.0.2/24"
:local vpsTunnelIP "10.200.0.1"

# Red de Proxmox (VMs locales)
:local proxmoxNetwork "10.100.0.0/24"

# Nombre de la interfaz WireGuard
:local wgInterfaceName "wireguard1"

# =============================================================================
# INICIO DEL SCRIPT
# =============================================================================

:put "═════════════════════════════════════════════════════════════════"
:put "  MikroTik WireGuard Setup - Client Configuration"
:put "═════════════════════════════════════════════════════════════════"
:put ""

# =============================================================================
# 1. VERIFICAR VERSIÓN DE ROUTEROS
# =============================================================================

:put "[INFO] Verificando versión de RouterOS..."

:local rosVersion [/system resource get version]
:put "  RouterOS Version: $rosVersion"

# Verificar que sea versión 7.x (WireGuard nativo)
:if ([:pick $rosVersion 0 1] < "7") do={
    :put "[ERROR] RouterOS 7.x o superior es requerido para WireGuard nativo"
    :put "[ERROR] Versión actual: $rosVersion"
    :put "[ERROR] Por favor actualiza RouterOS antes de continuar"
    :error "RouterOS version incompatible"
}

:put "[OK] Versión compatible detectada"
:put ""

# =============================================================================
# 2. ELIMINAR CONFIGURACIÓN ANTERIOR (SI EXISTE)
# =============================================================================

:put "[INFO] Limpiando configuración anterior..."

# Eliminar peer anterior
:if ([/interface/wireguard/peers print count-only] > 0) do={
    :put "  Eliminando peers de WireGuard anteriores..."
    /interface/wireguard/peers remove [find]
}

# Eliminar interfaz anterior
:if ([:len [/interface/wireguard find name=$wgInterfaceName]] > 0) do={
    :put "  Eliminando interfaz WireGuard anterior..."
    /interface/wireguard remove [find name=$wgInterfaceName]
}

:put "[OK] Limpieza completada"
:put ""

# =============================================================================
# 3. CREAR INTERFAZ WIREGUARD
# =============================================================================

:put "[INFO] Creando interfaz WireGuard..."

/interface/wireguard add \
    name=$wgInterfaceName \
    private-key=$clientPrivateKey \
    listen-port=$wgPort \
    mtu=1420 \
    comment="Tunel a VPS Datacenter"

:put "[OK] Interfaz WireGuard creada: $wgInterfaceName"
:put ""

# =============================================================================
# 4. ASIGNAR IP AL TÚNEL
# =============================================================================

:put "[INFO] Asignando IP al túnel..."

/ip/address add \
    address=$mikrotikTunnelIP \
    interface=$wgInterfaceName \
    comment="WireGuard Tunnel IP"

:put "[OK] IP asignada: $mikrotikTunnelIP"
:put ""

# =============================================================================
# 5. CONFIGURAR PEER (SERVIDOR VPS)
# =============================================================================

:put "[INFO] Configurando peer (VPS)..."

/interface/wireguard/peers add \
    interface=$wgInterfaceName \
    public-key=$serverPublicKey \
    endpoint-address=$vpsPublicIP \
    endpoint-port=$wgPort \
    allowed-address=0.0.0.0/0 \
    persistent-keepalive=25s \
    comment="VPS Datacenter Endpoint"

:put "[OK] Peer configurado"
:put "  Endpoint: $vpsPublicIP:$wgPort"
:put "  Public Key: $serverPublicKey"
:put ""

# =============================================================================
# 6. CONFIGURAR RUTAS
# =============================================================================

:put "[INFO] Configurando rutas..."

# Ruta al servidor VPS por el túnel
/ip/route add \
    dst-address="$vpsTunnelIP/32" \
    gateway=$wgInterfaceName \
    comment="Route to VPS via WireGuard"

:put "[OK] Ruta al VPS configurada"
:put ""

# =============================================================================
# 7. CONFIGURAR FIREWALL
# =============================================================================

:put "[INFO] Configurando firewall..."

# Permitir tráfico establecido/relacionado del túnel
/ip/firewall/filter add \
    chain=input \
    connection-state=established,related \
    in-interface=$wgInterfaceName \
    action=accept \
    comment="WireGuard: Allow established/related" \
    place-before=0

# Permitir tráfico del túnel WireGuard
/ip/firewall/filter add \
    chain=input \
    in-interface=$wgInterfaceName \
    action=accept \
    comment="WireGuard: Allow tunnel traffic" \
    place-before=1

# Permitir forward desde red local al túnel
/ip/firewall/filter add \
    chain=forward \
    src-address=$proxmoxNetwork \
    out-interface=$wgInterfaceName \
    action=accept \
    comment="WireGuard: Allow LAN to tunnel" \
    place-before=0

# Permitir forward desde túnel a red local
/ip/firewall/filter add \
    chain=forward \
    in-interface=$wgInterfaceName \
    dst-address=$proxmoxNetwork \
    action=accept \
    comment="WireGuard: Allow tunnel to LAN" \
    place-before=1

:put "[OK] Reglas de firewall configuradas"
:put ""

# =============================================================================
# 8. VERIFICACIÓN
# =============================================================================

:put "═════════════════════════════════════════════════════════════════"
:put "  VERIFICACIÓN DE CONFIGURACIÓN"
:put "═════════════════════════════════════════════════════════════════"
:put ""

# Mostrar interfaz WireGuard
:put "[INFO] Interfaz WireGuard:"
/interface/wireguard print detail where name=$wgInterfaceName

:put ""

# Mostrar peers
:put "[INFO] Peers configurados:"
/interface/wireguard/peers print detail

:put ""

# Mostrar IP asignada
:put "[INFO] IP del túnel:"
/ip/address print where interface=$wgInterfaceName

:put ""

# =============================================================================
# 9. TEST DE CONECTIVIDAD
# =============================================================================

:put "═════════════════════════════════════════════════════════════════"
:put "  TEST DE CONECTIVIDAD"
:put "═════════════════════════════════════════════════════════════════"
:put ""

:put "[INFO] Esperando 5 segundos para que el túnel se establezca..."
:delay 5s

:put "[INFO] Haciendo ping al VPS por el túnel..."
:if ([/ping $vpsTunnelIP count=4] > 0) do={
    :put "[OK] ✓ Conectividad con VPS establecida"
} else={
    :put "[WARNING] ✗ No hay respuesta del VPS"
    :put "[WARNING] Verifica que el servidor VPS esté corriendo"
    :put "[WARNING] Comando de verificación en VPS: systemctl status wg-quick@wg0"
}

:put ""

# =============================================================================
# 10. INFORMACIÓN POST-INSTALACIÓN
# =============================================================================

:put "═════════════════════════════════════════════════════════════════"
:put "  CONFIGURACIÓN COMPLETADA"
:put "═════════════════════════════════════════════════════════════════"
:put ""
:put "Próximos pasos:"
:put ""
:put "1. Verificar estado del túnel:"
:put "   /interface/wireguard/peers print"
:put ""
:put "2. Ver estadísticas de tráfico:"
:put "   /interface/wireguard print stats"
:put ""
:put "3. Configurar NAT y routing:"
:put "   /import 02-configure-nat.rsc"
:put ""
:put "4. Hacer ping manual al VPS:"
:put "   /ping $vpsTunnelIP count=10"
:put ""
:put "═════════════════════════════════════════════════════════════════"
:put ""

:put "[SUCCESS] ✅ WireGuard configurado exitosamente en MikroTik"
