################################################################################
# MikroTik NAT and Routing Configuration
# Descripción: Configuración de NAT Source y Policy Routing para VMs
#
# IMPORTANTE:
# 1. Ejecutar DESPUÉS de 01-setup-wireguard.rsc
# 2. Edita las variables con las IPs de tus VMs
# 3. Ejecuta: /import 02-configure-nat.rsc
################################################################################

# =============================================================================
# VARIABLES DE CONFIGURACIÓN - EDITAR ESTAS LÍNEAS
# =============================================================================

# Nombre de la interfaz WireGuard (debe coincidir con script anterior)
:local wgInterface "wireguard1"

# IP del VPS en el túnel
:local vpsTunnelIP "10.200.0.1"

# Red de Proxmox
:local proxmoxNetwork "10.100.0.0/24"

# IPs de las VMs que usarán las IPs públicas del datacenter
# IMPORTANTE: Agregar todas las IPs de VMs que necesiten salir por el túnel
:local vmIPs {
    "10.100.0.11";
    "10.100.0.12";
    "10.100.0.13";
    "10.100.0.14";
    "10.100.0.15"
}

# Nombres descriptivos de las VMs (opcional, para comentarios)
:local vmNames {
    "web-server-1";
    "web-server-2";
    "database-1";
    "app-server-1";
    "mail-server-1"
}

# =============================================================================
# INICIO DEL SCRIPT
# =============================================================================

:put "═════════════════════════════════════════════════════════════════"
:put "  MikroTik NAT & Routing Configuration"
:put "═════════════════════════════════════════════════════════════════"
:put ""

# =============================================================================
# 1. VERIFICAR QUE WIREGUARD ESTÉ CONFIGURADO
# =============================================================================

:put "[INFO] Verificando configuración de WireGuard..."

:if ([:len [/interface/wireguard find name=$wgInterface]] = 0) do={
    :put "[ERROR] Interfaz WireGuard '$wgInterface' no encontrada"
    :put "[ERROR] Ejecuta primero: /import 01-setup-wireguard.rsc"
    :error "WireGuard not configured"
}

:put "[OK] Interfaz WireGuard encontrada"
:put ""

# =============================================================================
# 2. LIMPIAR CONFIGURACIÓN ANTERIOR
# =============================================================================

:put "[INFO] Limpiando configuración NAT anterior..."

# Eliminar reglas NAT de WireGuard anteriores
:foreach rule in=[/ip/firewall/nat find comment~"WireGuard"] do={
    /ip/firewall/nat remove $rule
}

# Eliminar marcas de conexión anteriores
:foreach rule in=[/ip/firewall/mangle find comment~"WireGuard"] do={
    /ip/firewall/mangle remove $rule
}

:put "[OK] Limpieza completada"
:put ""

# =============================================================================
# 3. CONFIGURAR NAT SOURCE (SRCNAT)
# =============================================================================

:put "[INFO] Configurando NAT Source..."

# NAT para VMs específicas que deben salir por el túnel
:local count 0
:foreach vmIP in=$vmIPs do={
    :local vmName "VM"
    :if ($count < [:len $vmNames]) do={
        :set vmName [:pick $vmNames $count]
    }

    :put "  Configurando NAT para $vmIP ($vmName)..."

    # SRCNAT: Cambiar IP origen de la VM por IP del túnel
    # Esto hace que el tráfico de la VM salga por el túnel WireGuard
    /ip/firewall/nat add \
        chain=srcnat \
        src-address=$vmIP \
        out-interface=$wgInterface \
        action=masquerade \
        comment="WireGuard: SRCNAT for $vmName ($vmIP)"

    :put "    [OK] Regla SRCNAT creada"

    :set count ($count + 1)
}

:put "[OK] $count reglas de NAT Source configuradas"
:put ""

# =============================================================================
# 4. CONFIGURAR POLICY ROUTING (MANGLE)
# =============================================================================

:put "[INFO] Configurando Policy Routing con Mangle..."

# Marcar paquetes de las VMs para enrutarlos por el túnel
:set count 0
:foreach vmIP in=$vmIPs do={
    :local vmName "VM"
    :if ($count < [:len $vmNames]) do={
        :set vmName [:pick $vmNames $count]
    }

    :put "  Configurando routing para $vmIP ($vmName)..."

    # Marcar paquetes salientes de la VM
    /ip/firewall/mangle add \
        chain=prerouting \
        src-address=$vmIP \
        action=mark-routing \
        new-routing-mark=via-wireguard \
        passthrough=yes \
        comment="WireGuard: Mark routing for $vmName ($vmIP)"

    :put "    [OK] Marca de routing creada"

    :set count ($count + 1)
}

:put "[OK] $count reglas de mangle configuradas"
:put ""

# =============================================================================
# 5. CREAR TABLA DE ROUTING
# =============================================================================

:put "[INFO] Configurando tabla de routing..."

# Ruta por defecto para paquetes marcados → enviar por WireGuard
:if ([:len [/ip/route find comment="WireGuard: Default route for marked traffic"]] > 0) do={
    /ip/route remove [find comment="WireGuard: Default route for marked traffic"]
}

/ip/route add \
    dst-address=0.0.0.0/0 \
    gateway=$vpsTunnelIP \
    routing-mark=via-wireguard \
    distance=1 \
    comment="WireGuard: Default route for marked traffic"

:put "[OK] Tabla de routing configurada"
:put "  Todo el tráfico marcado saldrá por: $vpsTunnelIP (WireGuard)"
:put ""

# =============================================================================
# 6. CONFIGURAR DNS PARA VMs (OPCIONAL)
# =============================================================================

:put "[INFO] Configurando DNS forwarding..."

# Permitir que las VMs usen el DNS del MikroTik
/ip/dns/static/flush-cache

:put "[OK] Caché DNS limpiada"
:put ""

# =============================================================================
# 7. VERIFICACIÓN
# =============================================================================

:put "═════════════════════════════════════════════════════════════════"
:put "  VERIFICACIÓN DE CONFIGURACIÓN"
:put "═════════════════════════════════════════════════════════════════"
:put ""

# Mostrar reglas NAT
:put "[INFO] Reglas de NAT configuradas:"
/ip/firewall/nat print where comment~"WireGuard"

:put ""

# Mostrar reglas Mangle
:put "[INFO] Reglas de Mangle (Policy Routing):"
/ip/firewall/mangle print where comment~"WireGuard"

:put ""

# Mostrar rutas
:put "[INFO] Rutas configuradas:"
/ip/route print where comment~"WireGuard"

:put ""

# =============================================================================
# 8. TESTING
# =============================================================================

:put "═════════════════════════════════════════════════════════════════"
:put "  INSTRUCCIONES DE TESTING"
:put "═════════════════════════════════════════════════════════════════"
:put ""
:put "Verificar configuración:"
:put ""
:put "1. Desde una VM en Proxmox:"
:put "   ping $vpsTunnelIP"
:put "   (Debe responder - es el VPS por el túnel)"
:put ""
:put "2. Verificar que la VM sale con IP pública del datacenter:"
:put "   curl ifconfig.me"
:put "   (Debe mostrar una de las IPs públicas del VPS)"
:put ""
:put "3. Traceroute para ver la ruta:"
:put "   traceroute 8.8.8.8"
:put "   (Debe pasar por $vpsTunnelIP)"
:put ""
:put "4. Ver contadores de NAT en MikroTik:"
:put "   /ip/firewall/nat print stats"
:put ""
:put "5. Ver tráfico en tiempo real:"
:put "   /interface/wireguard print stats"
:put ""
:put "═════════════════════════════════════════════════════════════════"
:put ""

# =============================================================================
# 9. INFORMACIÓN DE DEBUG
# =============================================================================

:put "═════════════════════════════════════════════════════════════════"
:put "  COMANDOS DE DEBUG"
:put "═════════════════════════════════════════════════════════════════"
:put ""
:put "Si algo no funciona:"
:put ""
:put "1. Ver logs del firewall:"
:put "   /log print where topics~\"firewall\""
:put ""
:put "2. Habilitar logging temporal en NAT:"
:put "   /ip/firewall/nat set [find comment~\"WireGuard\"] log=yes"
:put ""
:put "3. Verificar que el paquete está siendo marcado:"
:put "   /ip/firewall/mangle print stats"
:put ""
:put "4. Ver rutas activas:"
:put "   /ip/route print detail where active=yes"
:put ""
:put "5. Packet sniffer (cuidado en producción):"
:put "   /tool sniffer quick interface=$wgInterface"
:put ""
:put "═════════════════════════════════════════════════════════════════"
:put ""

:put "[SUCCESS] ✅ NAT y Routing configurados exitosamente"
:put ""
:put "Próximos pasos:"
:put "  1. Configurar VMs en Proxmox con IPs estáticas"
:put "  2. Configurar gateway de VMs → IP del MikroTik"
:put "  3. Hacer pruebas de conectividad desde las VMs"
:put ""
