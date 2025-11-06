# Guía de Solución de Problemas - WireGuard Tunnel

## 🔧 Problemas Comunes y Soluciones

### 1. Túnel No Se Establece

#### Síntomas
- `wg show` muestra peer pero sin "latest handshake"
- MikroTik no aparece como conectado
- Ping a 10.200.0.1 o 10.200.0.2 falla

#### Diagnóstico

**En VPS:**
```bash
# Verificar que el servicio está corriendo
systemctl status wg-quick@wg0

# Ver logs
journalctl -u wg-quick@wg0 -n 50

# Verificar que el puerto está abierto
netstat -ulnp | grep 51820

# Verificar firewall
iptables -L INPUT -n | grep 51820
```

**En MikroTik:**
```
# Ver estado del peer
/interface/wireguard/peers/print detail

# Ver logs
/log/print where topics~"wireguard"

# Verificar endpoint
/interface/wireguard/peers/print
```

#### Soluciones

1. **Verificar claves públicas/privadas**
   ```bash
   # En VPS, verificar que la clave pública del cliente coincide
   cat /etc/wireguard/wg0.conf | grep PublicKey

   # Debe coincidir con la clave pública generada para el cliente
   cat /etc/wireguard/keys/client_public.key
   ```

2. **Verificar firewall en VPS**
   ```bash
   # Permitir puerto WireGuard
   iptables -A INPUT -p udp --dport 51820 -j ACCEPT
   netfilter-persistent save
   ```

3. **Verificar IP pública de oficina**
   - Confirmar que `OFFICE_PUBLIC_IP` en variables.env es correcta
   - Puede haber cambiado si el ISP asigna IPs dinámicas

4. **Reiniciar servicios**
   ```bash
   # En VPS
   systemctl restart wg-quick@wg0

   # En MikroTik
   /interface/wireguard/disable wireguard1
   /interface/wireguard/enable wireguard1
   ```

### 2. Túnel Conecta Pero No Hay Tráfico

#### Síntomas
- `wg show` muestra handshake reciente
- Ping a IP del túnel funciona (10.200.0.1 ↔ 10.200.0.2)
- Ping a Internet desde VM falla
- `curl ifconfig.me` desde VM muestra IP de oficina, no IP pública del datacenter

#### Diagnóstico

**En VPS:**
```bash
# Verificar IP forwarding
sysctl net.ipv4.ip_forward
# Debe retornar: net.ipv4.ip_forward = 1

# Verificar reglas NAT
iptables -t nat -L -n -v

# Ver si hay tráfico
tcpdump -i wg0 -n
```

**En MikroTik:**
```
# Verificar reglas NAT
/ip/firewall/nat/print stats

# Verificar rutas
/ip/route/print where active=yes

# Ver tráfico
/tool/torch interface=wireguard1
```

#### Soluciones

1. **Habilitar IP forwarding en VPS**
   ```bash
   sysctl -w net.ipv4.ip_forward=1
   echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
   sysctl -p
   ```

2. **Verificar NAT en VPS**
   ```bash
   # Debe existir masquerade para el túnel
   iptables -t nat -L POSTROUTING -n -v | grep 10.200

   # Si no existe, agregar
   iptables -t nat -A POSTROUTING -s 10.200.0.0/24 -o eth0 -j MASQUERADE
   netfilter-persistent save
   ```

3. **Verificar NAT en MikroTik**
   ```
   # Verificar que las reglas SRCNAT existen
   /ip/firewall/nat/print where chain=srcnat

   # Verificar contadores (packets y bytes deben incrementar)
   /ip/firewall/nat/print stats
   ```

4. **Verificar Mangle (Policy Routing)**
   ```
   # Verificar que los paquetes están siendo marcados
   /ip/firewall/mangle/print stats

   # Verificar ruta por defecto para paquetes marcados
   /ip/route/print where routing-mark=via-wireguard
   ```

### 3. Solo Algunas VMs Funcionan, Otras No

#### Síntomas
- VM1 sale con IP pública correcta
- VM2 sale con IP de oficina (incorrecta)
- Configuración aparentemente idéntica

#### Diagnóstico

```bash
# En VPS, verificar que existe NAT para esa VM
iptables -t nat -L -n -v | grep <IP_DE_VM>

# En MikroTik, verificar reglas
/ip/firewall/nat/print where src-address=<IP_DE_VM>
/ip/firewall/mangle/print where src-address=<IP_DE_VM>
```

#### Soluciones

1. **Agregar VM faltante**
   ```bash
   # En VPS
   ./scripts/vps/03-add-ip-mapping.sh <IP_PUBLICA> <IP_VM>

   # En MikroTik
   /import 03-add-vm.rsc
   # (Editar primero el archivo con IP de la VM)
   ```

2. **Verificar IP de la VM en Proxmox**
   ```bash
   # Desde la VM
   ip addr show

   # Debe coincidir exactamente con la configurada en scripts
   ```

3. **Verificar gateway de la VM**
   ```bash
   # Desde la VM
   ip route show default

   # Debe ser la IP del MikroTik en la red de Proxmox
   ```

### 4. Latencia Alta o Pérdida de Paquetes

#### Síntomas
- Ping funciona pero con latencia >100ms
- Pérdida intermitente de paquetes
- Conexiones lentas o inestables

#### Diagnóstico

```bash
# Ping continuo para ver pérdida
ping -c 100 10.200.0.2

# MTR para ver dónde está el problema
mtr 10.200.0.2

# Ver estadísticas de WireGuard
wg show wg0
```

#### Soluciones

1. **Ajustar MTU**
   ```bash
   # En VPS, editar /etc/wireguard/wg0.conf
   MTU = 1380  # Probar valores: 1420, 1400, 1380, 1360

   # Reiniciar
   systemctl restart wg-quick@wg0
   ```

   ```
   # En MikroTik
   /interface/wireguard/set wireguard1 mtu=1380
   ```

2. **Verificar congestión de red**
   ```bash
   # Ver uso de ancho de banda
   iftop -i wg0

   # Limitar si es necesario (Traffic Control)
   tc qdisc add dev wg0 root tbf rate 100mbit burst 32kbit latency 400ms
   ```

3. **Ajustar keepalive**
   ```
   # En MikroTik, reducir keepalive
   /interface/wireguard/peers/set [find] persistent-keepalive=15s
   ```

### 5. Conexión Se Cae Periódicamente

#### Síntomas
- Túnel funciona por minutos/horas
- Luego deja de responder
- Después de reiniciar vuelve a funcionar

#### Diagnóstico

```bash
# Ver logs del sistema
journalctl -u wg-quick@wg0 --since "1 hour ago"

# Verificar memoria y CPU
free -h
top -b -n 1 | head -20

# Ver si hay errores de red
dmesg | tail -50
```

#### Soluciones

1. **IP dinámica de oficina cambió**
   ```bash
   # Verificar IP actual de oficina
   curl ifconfig.me

   # Actualizar en variables.env si cambió
   OFFICE_PUBLIC_IP="nueva_ip"
   ```

2. **Firewall bloqueando**
   ```bash
   # Verificar logs de iptables
   journalctl -k | grep -i "iptables"

   # Permitir explícitamente
   iptables -I INPUT 1 -p udp --dport 51820 -j ACCEPT
   ```

3. **NAT del router de oficina**
   - Configurar port forwarding en router antes del MikroTik
   - UDP 51820 → MikroTik

4. **Agregar watchdog script**
   ```bash
   # /usr/local/bin/wg-watchdog.sh
   #!/bin/bash
   if ! ping -c 3 -W 5 10.200.0.2 > /dev/null 2>&1; then
       systemctl restart wg-quick@wg0
   fi

   # Agregar a cron cada 5 minutos
   */5 * * * * /usr/local/bin/wg-watchdog.sh
   ```

### 6. NAT 1:1 No Funciona (IP Pública Incorrecta)

#### Síntomas
- VM sale con IP del VPS principal, no con su IP asignada
- `curl ifconfig.me` desde VM muestra IP incorrecta

#### Diagnóstico

```bash
# Verificar que la IP pública está asignada a la interfaz
ip addr show eth0

# Verificar reglas SNAT
iptables -t nat -L POSTROUTING -n -v

# Tcpdump para ver qué IP de origen usa
tcpdump -i eth0 -n | grep <IP_DE_VM>
```

#### Soluciones

1. **Verificar que IP adicional está asignada**
   ```bash
   ip addr add <IP_PUBLICA>/32 dev eth0

   # Hacer permanente
   /etc/network/if-up.d/assign-additional-ips
   ```

2. **Verificar orden de reglas NAT**
   ```bash
   # Reglas SNAT específicas deben ir ANTES del masquerade general
   iptables -t nat -L POSTROUTING -n -v --line-numbers

   # Si el orden está mal, eliminar y re-crear
   iptables -t nat -D POSTROUTING <numero_de_linea>
   ./scripts/vps/02-configure-nat.sh
   ```

3. **Restaurar reglas NAT**
   ```bash
   /etc/wireguard/restore-nat.sh
   ```

### 7. Error "Permission Denied" o "Operation Not Permitted"

#### Síntomas
- Scripts fallan con errores de permisos
- iptables retorna "Operation not permitted"

#### Soluciones

1. **Ejecutar como root**
   ```bash
   sudo su -
   ./scripts/vps/01-setup-wireguard.sh
   ```

2. **Verificar capacidades del VPS**
   ```bash
   # Algunos VPS (OpenVZ) no permiten modificar iptables
   # Verificar tipo de virtualización
   systemd-detect-virt

   # Si es OpenVZ, solicitar al proveedor que habilite:
   # - TUN/TAP device
   # - iptables
   ```

### 8. RouterOS "Bad Request" al Importar Script

#### Síntomas
- Error al ejecutar `/import script.rsc`
- Sintaxis parece correcta

#### Soluciones

1. **Verificar formato de archivo**
   ```bash
   # Convertir líneas de Windows a Unix
   dos2unix scripts/mikrotik/*.rsc
   ```

2. **Copiar contenido manualmente**
   - Abrir el .rsc con editor de texto
   - Copiar líneas una por una en terminal SSH

3. **Usar WinBox**
   - Files → Upload script.rsc
   - New Terminal → Pegar contenido

## 🔍 Comandos de Debug Avanzados

### Captura de Paquetes Completa

```bash
# En VPS - Capturar todo el tráfico de una VM
tcpdump -i any -n "host 10.100.0.11" -w /tmp/vm-debug.pcap

# Descargar y analizar con Wireshark
scp root@vps:/tmp/vm-debug.pcap .
```

### Ver Conexiones Activas

```bash
# En VPS
ss -tunap | grep 51820

# Ver conexiones de una VM específica
conntrack -L | grep 10.100.0.11
```

### Verificar Ruta de Paquetes

```bash
# Desde VM
traceroute -n 8.8.8.8

# Debe mostrar:
# 1  10.100.0.1 (MikroTik)
# 2  10.200.0.1 (VPS en túnel)
# 3  <gateway del datacenter>
# ...
```

## 📞 Cuando Todo Falla

1. **Backup de configuración**
   ```bash
   # VPS
   cp /etc/wireguard/wg0.conf /root/wg0.conf.backup
   iptables-save > /root/iptables.backup

   # MikroTik
   /export file=backup-$(date +%Y%m%d)
   ```

2. **Eliminar y reconfigurar desde cero**
   ```bash
   # VPS
   systemctl stop wg-quick@wg0
   rm /etc/wireguard/wg0.conf
   ./scripts/vps/01-setup-wireguard.sh
   ./scripts/vps/02-configure-nat.sh

   # MikroTik
   /interface/wireguard/remove wireguard1
   /import 01-setup-wireguard.rsc
   ```

3. **Contactar soporte**
   - Incluir output de `wg show`
   - Logs de `journalctl -u wg-quick@wg0`
   - Output de `iptables -t nat -L -n -v`
   - Configuración (sin claves privadas)

## 📋 Checklist de Diagnóstico Rápido

- [ ] VPS: WireGuard service activo (`systemctl status wg-quick@wg0`)
- [ ] VPS: Puerto 51820 UDP abierto (`netstat -ulnp | grep 51820`)
- [ ] VPS: IP forwarding habilitado (`sysctl net.ipv4.ip_forward`)
- [ ] VPS: Reglas NAT configuradas (`iptables -t nat -L -n | grep -c DNAT`)
- [ ] VPS: Peer aparece con handshake reciente (`wg show`)
- [ ] MikroTik: WireGuard interface activo
- [ ] MikroTik: Peer conectado con endpoint correcto
- [ ] MikroTik: Reglas NAT y Mangle configuradas
- [ ] MikroTik: Ruta por defecto marcada existe
- [ ] Ping VPS → MikroTik funciona (`ping 10.200.0.2`)
- [ ] Ping MikroTik → VPS funciona (`/ping 10.200.0.1`)
- [ ] VM puede hacer ping al VPS
- [ ] VM sale con IP pública correcta (`curl ifconfig.me`)
