# Guía de Inicio Rápido - 10 Minutos

Esta guía te permite tener el túnel WireGuard funcionando en aproximadamente 10 minutos si ya tienes toda la información necesaria.

## ✅ Pre-requisitos

Antes de empezar, necesitas:

1. **VPS con Ubuntu/Debian**
   - Acceso root
   - IP pública principal
   - 10 IPs públicas adicionales ya asignadas
   - Puerto UDP 51820 abierto

2. **MikroTik RouterOS 7.x+**
   - Acceso admin
   - IP pública fija en la oficina

3. **Proxmox con VMs**
   - Red interna configurada (ej: 10.100.0.0/24)
   - VMs con IPs estáticas

## 🚀 Paso 1: Preparar Configuración (2 minutos)

```bash
# Clonar repo
git clone https://github.com/juliobrasa/router.git
cd router

# Copiar y editar configuración
cp config/variables.env.example config/variables.env
nano config/variables.env
```

**Editar solo estas líneas críticas:**

```bash
VPS_PUBLIC_IP="185.X.X.X"                    # IP principal del VPS
VPS_ADDITIONAL_IPS=("185.X.X.1" "185.X.X.2") # IPs adicionales
OFFICE_PUBLIC_IP="82.X.X.X"                  # IP pública de oficina
PROXMOX_NETWORK="10.100.0.0/24"              # Red de Proxmox
VM_IPS=("10.100.0.11" "10.100.0.12")        # IPs de VMs
VPS_INTERFACE="eth0"                         # Interfaz de red del VPS
```

Guardar y salir (Ctrl+O, Enter, Ctrl+X)

## 🖥️ Paso 2: Configurar VPS (4 minutos)

```bash
# Copiar archivos al VPS
scp config/variables.env root@185.X.X.X:/root/
scp -r scripts/vps/*.sh root@185.X.X.X:/root/

# Conectar al VPS
ssh root@185.X.X.X

# Ejecutar configuración
cd /root
chmod +x *.sh
./01-setup-wireguard.sh
```

**⚠️ IMPORTANTE:** Al terminar, copia y guarda las claves mostradas:
- Server Public Key
- Client Private Key

```bash
# Configurar NAT
./02-configure-nat.sh
```

## 🔧 Paso 3: Configurar MikroTik (3 minutos)

**Opción A: SSH**

```bash
# Desde tu máquina
scp scripts/mikrotik/*.rsc admin@192.168.88.1:

# Conectar a MikroTik
ssh admin@192.168.88.1
```

**Opción B: WinBox (más fácil)**
1. Abrir WinBox
2. Files → Arrastrar archivos .rsc
3. New Terminal

**Editar y ejecutar:**

```bash
# En tu editor (no en MikroTik todavía):
# Abrir: scripts/mikrotik/01-setup-wireguard.rsc

# Reemplazar al inicio del archivo:
:local vpsPublicIP "185.X.X.X"           # IP del VPS
:local serverPublicKey "PASTE_AQUI"      # Del paso 2
:local clientPrivateKey "PASTE_AQUI"     # Del paso 2

# Guardar el archivo
```

**En MikroTik:**

```
# Importar WireGuard
/import 01-setup-wireguard.rsc

# Esperar ~30 segundos

# Verificar
/ping 10.200.0.1 count=5
```

Debe responder con 0% packet loss.

**Editar NAT:**

```bash
# En tu editor:
# Abrir: scripts/mikrotik/02-configure-nat.rsc

# Reemplazar:
:local vmIPs {
    "10.100.0.11";
    "10.100.0.12"
}
```

**En MikroTik:**

```
/import 02-configure-nat.rsc
```

## 🖼️ Paso 4: Configurar VMs (1 minuto por VM)

En cada VM, configurar red estática:

**Ejemplo Ubuntu:**

```bash
# Editar netplan
sudo nano /etc/netplan/01-netcfg.yaml
```

```yaml
network:
  version: 2
  ethernets:
    ens18:
      addresses:
        - 10.100.0.11/24
      gateway4: 10.100.0.1    # IP del MikroTik
      nameservers:
        addresses:
          - 8.8.8.8
          - 1.1.1.1
```

```bash
sudo netplan apply
```

## ✅ Paso 5: Verificar (30 segundos)

**Desde cada VM:**

```bash
# 1. Ping al VPS
ping 10.200.0.1 -c 3

# 2. Verificar IP pública (¡CRÍTICO!)
curl ifconfig.me
```

**Debe mostrar la IP pública asignada a esa VM, no la IP de la oficina.**

## 🎉 ¡Listo!

Si `curl ifconfig.me` muestra la IP pública correcta, el sistema está funcionando.

## 🔥 Solución Rápida de Problemas

**VM muestra IP de oficina, no IP del VPS:**

```bash
# En VPS, verificar NAT
iptables -t nat -L -n | grep 10.100.0.11

# Si no aparece, agregar
./03-add-ip-mapping.sh 185.X.X.1 10.100.0.11
```

**Túnel no conecta:**

```bash
# En VPS
wg show

# Debe mostrar "latest handshake" < 2 minutos
# Si no, revisar claves públicas/privadas
```

**Sin Internet en VM:**

```bash
# Verificar gateway en VM
ip route show default

# Debe ser la IP del MikroTik
# Si no, reconfigurar red de la VM
```

## 📚 Documentación Completa

Para configuración avanzada, troubleshooting y monitoreo:

- [README.md](README.md) - Documentación completa
- [docs/configuration-checklist.md](docs/configuration-checklist.md) - Checklist paso a paso
- [docs/troubleshooting.md](docs/troubleshooting.md) - Solución de problemas
- [docs/monitoring.md](docs/monitoring.md) - Monitoreo del sistema

## 💡 Próximos Pasos

1. Configurar monitoreo:
   ```bash
   # En VPS
   cp scripts/vps/04-monitor.sh /usr/local/bin/wg-monitor.sh
   chmod +x /usr/local/bin/wg-monitor.sh
   ```

2. Agregar más VMs:
   ```bash
   # VPS
   ./03-add-ip-mapping.sh <IP_PUBLICA> <IP_VM>

   # MikroTik (editar 03-add-vm.rsc primero)
   /import 03-add-vm.rsc
   ```

3. Hacer backup de configuración:
   ```bash
   # VPS
   cp /etc/wireguard/wg0.conf /root/backup/

   # MikroTik
   /export file=backup
   ```

---

**¿Problemas?** Consulta [docs/troubleshooting.md](docs/troubleshooting.md) o abre un issue en GitHub.
