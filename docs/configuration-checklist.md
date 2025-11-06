# Checklist de Configuración - Sistema WireGuard Tunnel

## 📋 Pre-requisitos

### Información Necesaria Antes de Empezar

- [ ] **VPS Datacenter:**
  - [ ] IP pública principal: _______________
  - [ ] IPs públicas adicionales (lista completa):
    - [ ] IP 1: _______________
    - [ ] IP 2: _______________
    - [ ] IP 3: _______________
    - [ ] IP 4: _______________
    - [ ] IP 5: _______________
  - [ ] Interfaz de red principal (eth0, ens3, etc.): _______________
  - [ ] Acceso root (SSH)
  - [ ] Puerto UDP 51820 abierto en firewall

- [ ] **Oficina:**
  - [ ] IP pública fija: _______________
  - [ ] Usuario/contraseña admin MikroTik
  - [ ] IP interna MikroTik: _______________
  - [ ] Modelo MikroTik: _______________
  - [ ] Versión RouterOS: _______________ (debe ser 7.x+)

- [ ] **Proxmox:**
  - [ ] Red interna: _______________ /24
  - [ ] Gateway (MikroTik en red Proxmox): _______________
  - [ ] Lista de VMs con sus IPs:
    - [ ] VM 1: _______________ (IP: _______________)
    - [ ] VM 2: _______________ (IP: _______________)
    - [ ] VM 3: _______________ (IP: _______________)
    - [ ] VM 4: _______________ (IP: _______________)
    - [ ] VM 5: _______________ (IP: _______________)

- [ ] **Mapeo IP Pública → VM (debe ser 1:1):**
  - [ ] IP Pública 1 → VM 1
  - [ ] IP Pública 2 → VM 2
  - [ ] IP Pública 3 → VM 3
  - [ ] IP Pública 4 → VM 4
  - [ ] IP Pública 5 → VM 5

## 🚀 Fase 1: Preparación

- [ ] Clonar repositorio:
  ```bash
  git clone https://github.com/juliobrasa/router.git
  cd router
  ```

- [ ] Copiar archivo de variables:
  ```bash
  cp config/variables.env.example config/variables.env
  ```

- [ ] Editar `config/variables.env` con todos los valores reales

- [ ] Validar configuración:
  ```bash
  source config/variables.env
  _validate_config
  ```

## 🖥️ Fase 2: Configuración del VPS

### 2.1 Acceso al VPS

- [ ] Conectar al VPS por SSH:
  ```bash
  ssh root@<VPS_PUBLIC_IP>
  ```

- [ ] Crear directorio de trabajo:
  ```bash
  mkdir -p /root/wireguard-setup
  ```

- [ ] Copiar archivos necesarios al VPS:
  ```bash
  # Desde tu máquina local
  scp config/variables.env root@<VPS_IP>:/root/wireguard-setup/
  scp -r scripts/vps/* root@<VPS_IP>:/root/wireguard-setup/
  ```

### 2.2 Instalación de WireGuard

- [ ] Ejecutar script de instalación:
  ```bash
  cd /root/wireguard-setup
  chmod +x *.sh
  ./01-setup-wireguard.sh
  ```

- [ ] Verificar que no hubo errores en la ejecución

- [ ] **IMPORTANTE**: Guardar las claves mostradas al final del script:
  - [ ] Server Private Key (guardar en lugar seguro)
  - [ ] Server Public Key: ___________________________
  - [ ] Client Private Key: ___________________________
  - [ ] Client Public Key: ___________________________

- [ ] Verificar estado de WireGuard:
  ```bash
  systemctl status wg-quick@wg0
  wg show
  ```

- [ ] Debe mostrar:
  - [ ] Servicio activo y corriendo
  - [ ] Interfaz wg0 con IP 10.200.0.1

### 2.3 Configuración NAT 1:1

- [ ] Ejecutar script de NAT:
  ```bash
  ./02-configure-nat.sh
  ```

- [ ] Verificar IPs públicas asignadas:
  ```bash
  ip addr show eth0 | grep inet
  ```

- [ ] Deben aparecer todas las IPs adicionales

- [ ] Verificar reglas NAT:
  ```bash
  iptables -t nat -L -n -v | grep 10.100
  ```

- [ ] Debe haber 2 reglas por cada VM (DNAT y SNAT)

- [ ] Guardar configuración:
  ```bash
  netfilter-persistent save
  ```

### 2.4 Verificación VPS

- [ ] VPS puede hacer ping a sí mismo por el túnel:
  ```bash
  ping 10.200.0.1
  ```

- [ ] Logs no muestran errores:
  ```bash
  journalctl -u wg-quick@wg0 -n 20
  ```

## 🔧 Fase 3: Configuración del MikroTik

### 3.1 Acceso al MikroTik

- [ ] Conectar por SSH:
  ```bash
  ssh admin@<MIKROTIK_IP>
  ```

  O usar WinBox (recomendado para principiantes)

- [ ] Verificar versión de RouterOS:
  ```
  /system resource print
  ```

- [ ] Versión debe ser 7.x o superior

### 3.2 Copiar Scripts

- [ ] Transferir scripts al MikroTik:
  ```bash
  # Opción 1: SCP
  scp scripts/mikrotik/*.rsc admin@<MIKROTIK_IP>:

  # Opción 2: WinBox → Files → Drag & Drop
  ```

### 3.3 Editar Script de WireGuard

- [ ] Abrir `01-setup-wireguard.rsc` con editor de texto

- [ ] Reemplazar variables al principio del script:
  - [ ] `vpsPublicIP`: IP pública del VPS
  - [ ] `wgPort`: 51820
  - [ ] `clientPrivateKey`: Del output del script VPS
  - [ ] `serverPublicKey`: Del output del script VPS
  - [ ] `mikrotikTunnelIP`: 10.200.0.2/24
  - [ ] `vpsTunnelIP`: 10.200.0.1
  - [ ] `proxmoxNetwork`: Red de Proxmox

- [ ] Guardar el archivo

### 3.4 Ejecutar Script de WireGuard

- [ ] Importar y ejecutar:
  ```
  /import 01-setup-wireguard.rsc
  ```

- [ ] Esperar a que termine (puede tomar 1-2 minutos)

- [ ] Verificar que no hubo errores

- [ ] Verificar interfaz WireGuard:
  ```
  /interface/wireguard/print detail
  ```

- [ ] Verificar peer:
  ```
  /interface/wireguard/peers/print detail
  ```

- [ ] El peer debe mostrar:
  - [ ] Endpoint: IP del VPS
  - [ ] Estado: conectado

### 3.5 Editar Script de NAT

- [ ] Abrir `02-configure-nat.rsc` con editor

- [ ] Actualizar array de `vmIPs` con las IPs de tus VMs

- [ ] Actualizar array de `vmNames` (opcional)

- [ ] Guardar

### 3.6 Ejecutar Script de NAT

- [ ] Importar y ejecutar:
  ```
  /import 02-configure-nat.rsc
  ```

- [ ] Verificar reglas NAT:
  ```
  /ip/firewall/nat/print where comment~"WireGuard"
  ```

- [ ] Verificar reglas Mangle:
  ```
  /ip/firewall/mangle/print where comment~"WireGuard"
  ```

- [ ] Verificar rutas:
  ```
  /ip/route/print where comment~"WireGuard"
  ```

### 3.7 Verificación MikroTik

- [ ] Hacer ping al VPS por el túnel:
  ```
  /ping 10.200.0.1 count=10
  ```

- [ ] Debe tener 100% de respuestas

- [ ] Ver estadísticas de WireGuard:
  ```
  /interface/wireguard/print stats
  ```

- [ ] TX y RX deben ser > 0

## 🖼️ Fase 4: Configuración de VMs en Proxmox

Para cada VM que debe usar una IP pública:

### 4.1 Configuración de Red en la VM

- [ ] **VM 1 (IP: _______________ → IP Pública: _______________):**
  - [ ] Asignar IP estática en la VM
  - [ ] Configurar gateway: IP del MikroTik en red Proxmox
  - [ ] Configurar DNS: 8.8.8.8, 1.1.1.1
  - [ ] Reiniciar red o VM

- [ ] **VM 2 (IP: _______________ → IP Pública: _______________):**
  - [ ] Asignar IP estática
  - [ ] Gateway y DNS configurados
  - [ ] Red reiniciada

- [ ] **VM 3, 4, 5...** (repetir para cada VM)

### 4.2 Ejemplo de Configuración

**Ubuntu/Debian** (`/etc/netplan/01-netcfg.yaml`):
```yaml
network:
  version: 2
  ethernets:
    ens18:
      addresses:
        - 10.100.0.11/24
      gateway4: 10.100.0.1
      nameservers:
        addresses:
          - 8.8.8.8
          - 1.1.1.1
```

**CentOS/RHEL** (`/etc/sysconfig/network-scripts/ifcfg-eth0`):
```
BOOTPROTO=static
IPADDR=10.100.0.11
NETMASK=255.255.255.0
GATEWAY=10.100.0.1
DNS1=8.8.8.8
DNS2=1.1.1.1
```

## ✅ Fase 5: Testing y Verificación

### 5.1 Test de Conectividad Básica

- [ ] **Desde VPS, hacer ping a MikroTik:**
  ```bash
  ping 10.200.0.2 -c 10
  ```
  - [ ] 100% de paquetes recibidos

- [ ] **Desde MikroTik, hacer ping a VPS:**
  ```
  /ping 10.200.0.1 count=10
  ```
  - [ ] 100% de paquetes recibidos

### 5.2 Test desde VMs

Para cada VM:

- [ ] **VM 1:**
  - [ ] Ping al MikroTik (gateway):
    ```bash
    ping 10.100.0.1 -c 5
    ```
  - [ ] Ping al VPS por túnel:
    ```bash
    ping 10.200.0.1 -c 5
    ```
  - [ ] Ping a Internet:
    ```bash
    ping 8.8.8.8 -c 5
    ```
  - [ ] **Verificar IP pública de salida (CRÍTICO):**
    ```bash
    curl ifconfig.me
    ```
    - [ ] Debe mostrar la IP pública asignada a esta VM
  - [ ] Traceroute para ver ruta:
    ```bash
    traceroute -n 8.8.8.8
    ```
    - [ ] Debe pasar por: 10.100.0.1 → 10.200.0.1 → Internet

- [ ] **VM 2, 3, 4, 5...** (repetir para cada VM)

### 5.3 Test de NAT 1:1

- [ ] **Desde Internet, hacer ping a cada IP pública:**
  ```bash
  ping <IP_PUBLICA_1>
  ```
  - [ ] Debe llegar a VM 1

- [ ] **Desde Internet, hacer curl a un servicio web en VM:**
  ```bash
  curl http://<IP_PUBLICA_1>
  ```
  - [ ] Debe responder la VM 1

### 5.4 Verificación de Logs

- [ ] **VPS - Sin errores en logs:**
  ```bash
  journalctl -u wg-quick@wg0 -n 50 --no-pager
  ```

- [ ] **MikroTik - Sin errores en logs:**
  ```
  /log/print where topics~"wireguard,error"
  ```

### 5.5 Verificación de Rendimiento

- [ ] **Test de velocidad desde VM:**
  ```bash
  curl -s https://raw.githubusercontent.com/sivel/speedtest-cli/master/speedtest.py | python3 -
  ```

- [ ] **Latencia aceptable (típicamente <50ms adicionales):**
  ```bash
  ping 8.8.8.8 -c 100 | tail -1
  ```

## 📊 Fase 6: Monitoreo y Mantenimiento

### 6.1 Configurar Monitoreo Básico

- [ ] Instalar script de monitoreo en VPS:
  ```bash
  cp /root/wireguard-setup/04-monitor.sh /usr/local/bin/wg-monitor.sh
  chmod +x /usr/local/bin/wg-monitor.sh
  ```

- [ ] Agregar a crontab para reporte diario:
  ```bash
  crontab -e
  # Agregar: 0 8 * * * /usr/local/bin/wg-monitor.sh
  ```

### 6.2 Configurar Alertas

- [ ] Crear watchdog script:
  ```bash
  nano /usr/local/bin/wg-watchdog.sh
  ```

- [ ] Agregar a cron cada 5 minutos:
  ```bash
  */5 * * * * /usr/local/bin/wg-watchdog.sh
  ```

### 6.3 Backup de Configuración

- [ ] **VPS:**
  ```bash
  cp /etc/wireguard/wg0.conf /root/backups/wg0.conf.$(date +%Y%m%d)
  iptables-save > /root/backups/iptables.$(date +%Y%m%d)
  ```

- [ ] **MikroTik:**
  ```
  /export file=wireguard-backup-$(date +%Y%m%d)
  ```

- [ ] Descargar backups a tu máquina local

## 📝 Documentación

- [ ] Completar este checklist con valores reales

- [ ] Documentar cualquier cambio o personalización

- [ ] Guardar claves en gestor de contraseñas seguro

- [ ] Agregar información de contacto para soporte:
  - Proveedor VPS: _______________
  - Contacto MikroTik: _______________
  - Contacto Proxmox: _______________

## 🎉 Completado

- [ ] Sistema funcionando correctamente

- [ ] Todas las VMs salen con sus IPs públicas asignadas

- [ ] Monitoreo configurado

- [ ] Backups realizados

- [ ] Documentación actualizada

---

**Fecha de instalación:** _______________

**Configurado por:** _______________

**Notas adicionales:**

_________________________________________________________________

_________________________________________________________________

_________________________________________________________________
