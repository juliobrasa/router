# Guía de Monitoreo - Sistema WireGuard Tunnel

## 📊 Monitoreo del VPS (Datacenter)

### Verificar Estado de WireGuard

```bash
# Ver estado general
systemctl status wg-quick@wg0

# Ver información detallada del túnel
wg show

# Ver con estadísticas
wg show all
```

**Output esperado**:
```
interface: wg0
  public key: <server_public_key>
  private key: (hidden)
  listening port: 51820

peer: <mikrotik_public_key>
  endpoint: Z.Z.Z.Z:51820
  allowed ips: 10.200.0.2/32, 10.100.0.0/24
  latest handshake: 45 seconds ago
  transfer: 1.25 GiB received, 987.32 MiB sent
  persistent keepalive: every 25 seconds
```

### Monitorear Tráfico en Tiempo Real

```bash
# Ver tráfico en la interfaz WireGuard
iftop -i wg0

# O con nload
nload wg0

# Ver estadísticas de red
watch -n1 'ip -s link show wg0'
```

### Verificar Reglas NAT

```bash
# Ver todas las reglas NAT
iptables -t nat -L -n -v

# Ver solo reglas de WireGuard
iptables -t nat -L -n -v | grep 10.100

# Ver estadísticas de NAT
watch -n2 'iptables -t nat -L -n -v | grep 10.100'
```

### Logs del Sistema

```bash
# Logs de WireGuard
journalctl -u wg-quick@wg0 -f

# Logs de las últimas 100 líneas
journalctl -u wg-quick@wg0 -n 100

# Logs desde una hora específica
journalctl -u wg-quick@wg0 --since "1 hour ago"

# Logs con errores solamente
journalctl -u wg-quick@wg0 -p err
```

### Tcpdump para Debugging

```bash
# Capturar tráfico en WireGuard
tcpdump -i wg0 -n

# Capturar solo de una VM específica
tcpdump -i wg0 host 10.100.0.11 -n

# Guardar captura para análisis
tcpdump -i wg0 -w /tmp/wireguard-$(date +%Y%m%d-%H%M%S).pcap

# Ver DNS queries
tcpdump -i wg0 port 53 -n
```

### Script de Monitoreo Automático

Crear `/usr/local/bin/wg-monitor.sh`:

```bash
#!/bin/bash

echo "═══════════════════════════════════════════════════════════"
echo "WireGuard Tunnel Monitor - $(date)"
echo "═══════════════════════════════════════════════════════════"
echo ""

# Estado del servicio
echo "🔹 Estado del Servicio:"
systemctl is-active wg-quick@wg0 && echo "  ✓ Activo" || echo "  ✗ Inactivo"
echo ""

# Información del túnel
echo "🔹 Estado del Túnel:"
wg show wg0 | head -5
echo ""

# Peer conectado
echo "🔹 Último Handshake:"
wg show wg0 latest-handshakes
echo ""

# Transferencia
echo "🔹 Transferencia de Datos:"
wg show wg0 transfer
echo ""

# Verificar conectividad
echo "🔹 Conectividad con MikroTik:"
if ping -c 2 -W 2 10.200.0.2 > /dev/null 2>&1; then
    echo "  ✓ MikroTik responde"
else
    echo "  ✗ MikroTik no responde"
fi
echo ""

# Reglas NAT activas
echo "🔹 Reglas NAT Activas:"
iptables -t nat -L PREROUTING -n | grep -c "DNAT" || echo "0"
echo ""

# Uso de CPU y RAM
echo "🔹 Recursos del Sistema:"
echo "  CPU: $(top -bn1 | grep "Cpu(s)" | awk '{print $2}')%"
echo "  RAM: $(free -h | grep Mem | awk '{print $3 "/" $2}')"
echo ""
```

Hacer ejecutable y agregar a cron:

```bash
chmod +x /usr/local/bin/wg-monitor.sh

# Agregar a crontab para reporte diario
echo "0 8 * * * /usr/local/bin/wg-monitor.sh | mail -s 'WireGuard Daily Report' admin@example.com" | crontab -
```

### Alertas Automáticas

Crear `/usr/local/bin/wg-check.sh`:

```bash
#!/bin/bash

# Verificar que WireGuard está activo
if ! systemctl is-active --quiet wg-quick@wg0; then
    echo "ALERTA: WireGuard no está activo" | mail -s "WireGuard DOWN" admin@example.com
    systemctl start wg-quick@wg0
fi

# Verificar conectividad con MikroTik
if ! ping -c 3 -W 5 10.200.0.2 > /dev/null 2>&1; then
    echo "ALERTA: No hay conectividad con MikroTik" | mail -s "WireGuard Connectivity Issue" admin@example.com
fi
```

Agregar a cron cada 5 minutos:

```bash
*/5 * * * * /usr/local/bin/wg-check.sh
```

## 🔍 Monitoreo del MikroTik (Oficina)

### Verificar Estado de WireGuard

```
# Estado de la interfaz
/interface/wireguard/print

# Estado de los peers
/interface/wireguard/peers/print

# Estadísticas
/interface/wireguard/print stats
```

### Ver Tráfico en Tiempo Real

```
# Herramienta de tráfico
/tool/traffic-monitor interface=wireguard1

# Gráfico de tráfico
/interface/wireguard/print stats interval=1

# Torch (similar a wireshark)
/tool/torch interface=wireguard1
```

### Verificar Reglas de Firewall

```
# Ver reglas NAT
/ip/firewall/nat/print stats

# Ver reglas Mangle
/ip/firewall/mangle/print stats

# Ver reglas Filter
/ip/firewall/filter/print where interface=wireguard1
```

### Verificar Rutas

```
# Ver todas las rutas
/ip/route/print detail

# Ver solo rutas de WireGuard
/ip/route/print where comment~"WireGuard"

# Ver rutas activas
/ip/route/print where active=yes
```

### Logs

```
# Ver logs recientes
/log/print

# Ver solo logs de WireGuard
/log/print where topics~"wireguard"

# Ver logs de firewall
/log/print where topics~"firewall"

# Seguir logs en tiempo real (en terminal SSH)
/log/print follow
```

### Gráficos de Monitoreo

Habilitar gráficos en MikroTik:

```
# Habilitar sistema de gráficos
/tool/graphing/interface/add interface=wireguard1

# Ver gráficos vía web
# http://<mikrotik-ip>/graphs/
```

### SNMP Monitoring (Opcional)

Habilitar SNMP para integrar con Zabbix/Prometheus:

```
# Habilitar SNMP
/snmp/set enabled=yes contact="admin@example.com" location="Oficina"

# Agregar comunidad
/snmp/community/add name=public addresses=0.0.0.0/0
```

## 📈 Métricas Clave a Monitorear

### VPS (Datacenter)

1. **Estado del Túnel**
   - `latest handshake` debe ser < 2 minutos
   - Si es mayor, hay problema de conectividad

2. **Transferencia de Datos**
   - Bytes received/sent deben aumentar
   - Si está en 0, no hay tráfico

3. **Reglas NAT**
   - Contadores de paquetes deben incrementar
   - Si están en 0, las VMs no están enrutando correctamente

4. **CPU y RAM**
   - WireGuard usa muy pocos recursos
   - Si CPU > 10%, investigar

5. **Logs de Errores**
   - No debe haber errores en journalctl

### MikroTik (Oficina)

1. **Estado del Peer**
   - Debe mostrar "connected"
   - `current-endpoint-address` debe ser la IP del VPS

2. **Tráfico**
   - TX y RX deben incrementar
   - Si están estáticos, no hay tráfico

3. **Rutas Activas**
   - Ruta por defecto marcada debe estar activa
   - `distance` debe ser correcto

4. **Reglas de Firewall**
   - Contadores de paquetes en NAT deben incrementar
   - Contadores de mangle deben incrementar

## 🚨 Alertas y Umbrales

### Críticas (Actuar Inmediatamente)

- WireGuard service down
- Handshake > 5 minutos
- 0 bytes transferred en 10 minutos
- Ping al peer falla 3 veces consecutivas

### Advertencias (Investigar)

- Handshake > 2 minutos
- Uso de CPU > 30%
- Logs con errores
- Contadores NAT no incrementan

## 📱 Dashboard de Monitoreo (Opcional)

### Grafana + Prometheus

1. Instalar node_exporter en VPS
2. Configurar Prometheus para scraping
3. Crear dashboard en Grafana con:
   - Estado del túnel WireGuard
   - Gráfica de tráfico
   - Latencia del túnel
   - Reglas NAT activas
   - Logs recientes

### Script Simple de Dashboard

```bash
#!/bin/bash
# /usr/local/bin/wg-dashboard.sh

watch -n5 '
clear
echo "═══════════════════════════════════════════════════════════"
echo "     WireGuard Tunnel Dashboard - $(date +"%H:%M:%S")"
echo "═══════════════════════════════════════════════════════════"
echo ""
echo "🔹 Túnel: $(systemctl is-active wg-quick@wg0 && echo "✓ UP" || echo "✗ DOWN")"
echo ""
echo "🔹 Último Handshake:"
wg show wg0 latest-handshakes | awk "{print \"  Peer:\", \$2, \"segundos atrás\"}"
echo ""
echo "🔹 Transferencia (MB):"
wg show wg0 transfer | awk "{print \"  RX:\", \$2/1024/1024, \"| TX:\", \$3/1024/1024}"
echo ""
echo "🔹 Conectividad:"
ping -c 1 -W 2 10.200.0.2 > /dev/null 2>&1 && echo "  ✓ MikroTik OK" || echo "  ✗ MikroTik NO RESPONDE"
echo ""
echo "🔹 NAT 1:1 Activas:"
iptables -t nat -L PREROUTING -n | grep -c "DNAT"
echo ""
'
```

## 📊 Ejemplos de Comandos de Monitoreo Rápido

```bash
# VPS - Health Check Rápido
wg show && ping -c 3 10.200.0.2 && iptables -t nat -L -n | grep -c DNAT

# MikroTik - Health Check Rápido
/interface/wireguard/peers/print && /ping 10.200.0.1 count=3

# Ver últimos 10 errores en VPS
journalctl -u wg-quick@wg0 -p err -n 10

# Ver estadísticas de una VM específica
iptables -t nat -L -n -v | grep 10.100.0.11
```
