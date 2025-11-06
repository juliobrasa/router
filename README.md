# Sistema de Túnel WireGuard - Datacenter → Oficina

## 📋 Resumen del Proyecto

Sistema completo de túnel VPN WireGuard para enrutar IPs públicas desde un VPS en datacenter hacia VMs en oficina a través de un router MikroTik.

### Arquitectura

```
┌─────────────────────────────────────────────────────────────────┐
│                    DATACENTER VPS                               │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  IP Principal: X.X.X.X                                    │  │
│  │  IPs Adicionales: Y.Y.Y.1 - Y.Y.Y.10                     │  │
│  │                                                           │  │
│  │  ┌─────────────────────────────────────────────────┐    │  │
│  │  │ WireGuard Server (wg0)                          │    │  │
│  │  │ IP Túnel: 10.200.0.1/24                        │    │  │
│  │  │                                                  │    │  │
│  │  │ NAT 1:1 Mapping:                                │    │  │
│  │  │ Y.Y.Y.1 → 10.100.0.11 (VM1)                    │    │  │
│  │  │ Y.Y.Y.2 → 10.100.0.12 (VM2)                    │    │  │
│  │  │ Y.Y.Y.3 → 10.100.0.13 (VM3)                    │    │  │
│  │  │ ...                                             │    │  │
│  │  └─────────────────────────────────────────────────┘    │  │
│  └──────────────────────────────────────────────────────────┘  │
└───────────────────────┬─────────────────────────────────────────┘
                        │
                   INTERNET
                        │
                        │ WireGuard Encrypted Tunnel
                        │ Puerto UDP 51820
                        │
┌───────────────────────┴─────────────────────────────────────────┐
│                    OFICINA                                       │
│  IP Pública Fija: Z.Z.Z.Z                                       │
│                                                                  │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │         MikroTik Router                                   │  │
│  │  ┌────────────────────────────────────────────────┐      │  │
│  │  │ WireGuard Client (wireguard1)                  │      │  │
│  │  │ IP Túnel: 10.200.0.2/24                       │      │  │
│  │  │                                                 │      │  │
│  │  │ NAT Source: Cambia IPs privadas → Túnel       │      │  │
│  │  │ Policy Routing: IPs especiales → Túnel        │      │  │
│  │  └────────────────────────────────────────────────┘      │  │
│  └──────────────────────────────────────────────────────────┘  │
│                              │                                   │
│  ┌──────────────────────────┴────────────────────────────────┐ │
│  │         Servidor Proxmox                                   │ │
│  │  Red Interna: 10.100.0.0/24                               │ │
│  │                                                            │ │
│  │  ┌────────────┐  ┌────────────┐  ┌────────────┐         │ │
│  │  │ VM1        │  │ VM2        │  │ VM3        │         │ │
│  │  │ 10.100.0.11│  │ 10.100.0.12│  │ 10.100.0.13│         │ │
│  │  │            │  │            │  │            │         │ │
│  │  │ Usa IP:    │  │ Usa IP:    │  │ Usa IP:    │         │ │
│  │  │ Y.Y.Y.1    │  │ Y.Y.Y.2    │  │ Y.Y.Y.3    │         │ │
│  │  └────────────┘  └────────────┘  └────────────┘         │ │
│  └────────────────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────────────────┘
```

## 🎯 Flujo de Tráfico

### Tráfico Saliente (VM → Internet)

1. **VM en Proxmox** (10.100.0.11) envía paquete a Internet
2. **MikroTik** detecta que es tráfico de una VM especial (policy routing)
3. **NAT Source** cambia IP de origen: 10.100.0.11 → 10.200.0.2 (IP túnel)
4. **WireGuard** encripta y envía por túnel al VPS
5. **VPS WireGuard** desencripta el paquete
6. **NAT 1:1 en VPS** cambia IP de origen: 10.200.0.2 → Y.Y.Y.1 (IP pública)
7. Paquete sale a Internet con IP pública Y.Y.Y.1

### Tráfico Entrante (Internet → VM)

1. **Internet** envía paquete a Y.Y.Y.1
2. **VPS iptables** detecta que es para Y.Y.Y.1
3. **DNAT** cambia IP destino: Y.Y.Y.1 → 10.100.0.11 (IP VM)
4. **WireGuard** encripta y envía por túnel al MikroTik
5. **MikroTik** desencripta y enruta a Proxmox
6. **VM** recibe el paquete

## 🔧 Componentes del Sistema

### 1. VPS (Datacenter)

**Función**: Gateway principal y endpoint WireGuard

- **WireGuard Server** en puerto UDP 51820
- **IP Túnel**: 10.200.0.1/24
- **NAT 1:1**: Mapea IPs públicas → IPs privadas de VMs
- **IP Forwarding** habilitado
- **Firewall** configurado para WireGuard + IPs públicas

### 2. MikroTik (Oficina)

**Función**: Cliente WireGuard y router principal de oficina

- **WireGuard Client** conectado al VPS
- **IP Túnel**: 10.200.0.2/24
- **NAT Source**: Cambia IPs privadas por IP túnel
- **Policy Routing**: Enruta VMs específicas por túnel
- **Firewall**: Permite tráfico WireGuard

### 3. Proxmox (Oficina)

**Función**: Hipervisor de VMs

- **Red Interna**: 10.100.0.0/24
- **Bridge**: vmbr0 conectado a MikroTik
- **VMs**: Cada VM tiene IP privada asignada

## 📦 Contenido del Repositorio

```
router/
├── README.md                        # Este archivo
├── docs/
│   ├── architecture.md             # Arquitectura detallada
│   ├── configuration-checklist.md  # Checklist de configuración
│   ├── monitoring.md               # Guía de monitoreo
│   └── troubleshooting.md          # Solución de problemas
├── scripts/
│   ├── vps/
│   │   ├── 01-setup-wireguard.sh   # Instalación WireGuard en VPS
│   │   ├── 02-configure-nat.sh     # Configuración NAT 1:1
│   │   ├── 03-add-ip-mapping.sh    # Agregar nueva IP
│   │   └── 04-monitor.sh           # Script de monitoreo
│   └── mikrotik/
│       ├── 01-setup-wireguard.rsc  # Configuración WireGuard
│       ├── 02-configure-nat.rsc    # Configuración NAT y routing
│       └── 03-add-vm.rsc           # Agregar nueva VM
├── config/
│   ├── vps-wireguard.conf.example  # Ejemplo config VPS
│   └── variables.env.example       # Variables de configuración
└── tests/
    ├── test-connectivity.sh        # Test de conectividad
    └── test-nat.sh                 # Test de NAT
```

## 🚀 Inicio Rápido

### Requisitos Previos

**VPS (Datacenter)**:
- Ubuntu 20.04/22.04 o Debian 11/12
- Acceso root
- IP pública principal
- 10 IPs públicas adicionales ya asignadas
- Puerto UDP 51820 abierto en firewall

**MikroTik (Oficina)**:
- RouterOS 7.x (WireGuard nativo)
- Acceso admin
- IP pública fija
- Conectividad con Proxmox

**Proxmox**:
- Red interna 10.100.0.0/24
- VMs con IPs estáticas asignadas

### Paso 1: Preparar Configuración

```bash
# Clonar repositorio
git clone https://github.com/juliobrasa/router.git
cd router

# Copiar archivo de variables
cp config/variables.env.example config/variables.env

# Editar variables
nano config/variables.env
```

**Variables a configurar** (ver archivo completo más abajo):
```env
# IPs del VPS
VPS_PUBLIC_IP=X.X.X.X
VPS_ADDITIONAL_IPS=("Y.Y.Y.1" "Y.Y.Y.2" "Y.Y.Y.3" "Y.Y.Y.4" "Y.Y.Y.5")

# IP pública de oficina
OFFICE_PUBLIC_IP=Z.Z.Z.Z

# Red Proxmox
PROXMOX_NETWORK=10.100.0.0/24

# IPs de VMs
VM_IPS=("10.100.0.11" "10.100.0.12" "10.100.0.13")
```

### Paso 2: Configurar VPS

```bash
# SSH al VPS
ssh root@X.X.X.X

# Copiar scripts
scp -r scripts/vps/* root@X.X.X.X:/root/wireguard-setup/

# En el VPS
cd /root/wireguard-setup

# 1. Instalar WireGuard
./01-setup-wireguard.sh

# 2. Configurar NAT 1:1
./02-configure-nat.sh

# Verificar estado
wg show
```

### Paso 3: Configurar MikroTik

```bash
# Copiar configuración
scp scripts/mikrotik/* admin@192.168.X.X:

# Conectar por SSH o WinBox
ssh admin@192.168.X.X

# Ejecutar scripts
/import 01-setup-wireguard.rsc
/import 02-configure-nat.rsc
```

### Paso 4: Verificar Conectividad

```bash
# En VPS
ping 10.200.0.2  # Ping a MikroTik por túnel

# En MikroTik
/ping 10.200.0.1  # Ping a VPS por túnel

# Test completo
bash tests/test-connectivity.sh
```

### Paso 5: Configurar VMs en Proxmox

1. Asignar IPs estáticas: 10.100.0.11, 10.100.0.12, 10.100.0.13
2. Gateway: 10.100.0.1 (MikroTik)
3. DNS: 8.8.8.8, 1.1.1.1

### Paso 6: Test Final

```bash
# Desde VM en Proxmox
curl ifconfig.me
# Debe mostrar Y.Y.Y.1 (IP pública del datacenter)

# Test desde Internet
curl http://Y.Y.Y.1
# Debe llegar a la VM
```

## 📊 Monitoreo

### Comandos Útiles

**VPS**:
```bash
# Estado WireGuard
wg show

# Tráfico en tiempo real
iptables -L -n -v | grep 10.200

# Logs
journalctl -u wg-quick@wg0 -f
```

**MikroTik**:
```bash
# Estado WireGuard
/interface/wireguard/peers/print

# Tráfico
/interface/wireguard/print stats

# Rutas
/ip/route/print where dst-address=10.200.0.0/24
```

**Pruebas desde VM**:
```bash
# Ver IP pública
curl ifconfig.me

# Traceroute
traceroute 8.8.8.8
```

## 🔒 Seguridad

### Buenas Prácticas Implementadas

1. **Encriptación**: WireGuard usa ChaCha20 + Poly1305
2. **Autenticación**: Claves públicas/privadas
3. **Firewall**: Solo tráfico autorizado
4. **NAT 1:1**: Aislamiento entre VMs
5. **Logs**: Auditoría completa de conexiones

### Puertos Abiertos

- **VPS**: UDP 51820 (WireGuard)
- **MikroTik**: UDP 51820 (saliente)

## 🆘 Solución de Problemas

### Túnel no conecta

```bash
# En VPS
systemctl status wg-quick@wg0
wg show

# En MikroTik
/log/print where topics~"wireguard"
```

### VMs no tienen IP pública correcta

```bash
# Verificar NAT en VPS
iptables -t nat -L -n -v | grep Y.Y.Y.1

# Verificar routing en MikroTik
/ip/route/print detail
```

### Sin conectividad a Internet

```bash
# Verificar IP forwarding en VPS
sysctl net.ipv4.ip_forward

# Verificar masquerade en VPS
iptables -t nat -L POSTROUTING -n -v
```

## 📚 Documentación Adicional

- [Arquitectura Detallada](docs/architecture.md)
- [Checklist de Configuración](docs/configuration-checklist.md)
- [Guía de Monitoreo](docs/monitoring.md)
- [Troubleshooting Avanzado](docs/troubleshooting.md)

## 🔄 Agregar Nuevas IPs/VMs

### Agregar nueva VM

```bash
# En VPS
./scripts/vps/03-add-ip-mapping.sh Y.Y.Y.6 10.100.0.14

# En MikroTik
./scripts/mikrotik/03-add-vm.rsc 10.100.0.14
```

## 📞 Soporte

- **Repositorio**: https://github.com/juliobrasa/router
- **Issues**: https://github.com/juliobrasa/router/issues

## 📝 Changelog

### v1.0.0 - 2025-11-06
- Configuración inicial del sistema
- Scripts de VPS completos
- Configuración MikroTik
- Documentación completa
- Tests de conectividad

## 📄 Licencia

MIT License - Ver LICENSE file para detalles

---

**Autor**: Julio Brasa
**Fecha**: Noviembre 2025
**Versión**: 1.0.0
