# Laboratório AD CS — ESC1 e ESC2

Conjunto de scripts e arquivos de configuração para reproduzir o laboratório
descrito no TCC **Análise de Vulnerabilidades em Active Directory Certificate
Services: Implementação de Laboratório para Estudo de Técnicas de Escalação de
Privilégios** (Cássio Bastos Alves, IFPB Campus João Pessoa, 2026).

O ambiente reproduz, de forma controlada, os vetores de exploração ESC1 e ESC2
catalogados por Schroeder e Christensen (2021) contra o subsistema *Active
Directory Certificate Services* (AD CS).

## Topologia

| Host | IP | Sistema operacional | Papel |
|------|-----|----------------------|-------|
| `DC01.tcc-adcs.local` | `10.10.10.10` | Windows Server 2022 Std Eval | Domain Controller + DNS |
| `CA01.tcc-adcs.local` | `10.10.10.11` | Windows Server 2022 Std Eval | Enterprise Root CA (AD CS) |
| `WS01.tcc-adcs.local` | `10.10.10.20` | Windows 11 Enterprise LTSC 2024 Eval | Estação *low-priv* |
| `kali` (host físico) | `10.10.10.1` | Kali Linux | Agente ofensivo |

Tudo na rede *host-only* `vmnet10` (`10.10.10.0/24`), sem rota para a rede externa.

## Credenciais do lab

Estas credenciais são apenas de laboratório isolado. Não use em ambiente real.

| Conta | Senha | Papel |
|-------|-------|-------|
| `TCCADCS\Administrator` | `Lab@TCC2026` | Conta padrão (autologon nas 3 VMs) |
| `cassio.aluno@tcc-adcs.local` | `Aluno@2026` | Usuário low-priv, membro de `DU-Enrollers` |

## Pré-requisitos

No host Linux (Kali ou similar):

- **VMware Workstation Pro** (versão gratuita para uso pessoal, disponível desde 2024)
- `vmware-vdiskmanager`, `vmware-networks`, `vmrun`, `vmware-modconfig` no PATH (acompanham o Workstation)
- `genisoimage`, `pipx`, `python3`, `base64`, `netcat`
- `certipy-ad` e `netexec` (instalar via `pipx`, ver abaixo)
- ~25 GB de espaço em disco para as 3 VMs

ISOs Windows a baixar manualmente:

- **Windows Server 2022 Standard Evaluation** (180 dias)
  <https://www.microsoft.com/en-us/evalcenter/evaluate-windows-server-2022>
- **Windows 11 Enterprise LTSC 2024 Evaluation**
  <https://www.microsoft.com/en-us/evalcenter/evaluate-windows-11-enterprise>

Salvar como:

```
iso/win-server-2022-eval.iso
iso/win11-eval.iso
```

## Setup do host (Ubuntu/Debian/Kali)

Testado no Kali Linux (rolling, kernel 6.19). Em Ubuntu 24.04 LTS e em Debian 12 deve funcionar com pequenas adaptações.

### 1. Pacotes do sistema

```bash
sudo apt update
sudo apt install -y \
    build-essential linux-headers-$(uname -r) \
    genisoimage pipx python3 netcat-openbsd \
    git curl
```

`build-essential` e os `linux-headers` são necessários para o VMware compilar os módulos `vmnet`/`vmmon` do kernel durante a instalação.

### 2. VMware Workstation Pro

Gratuito para uso pessoal desde 2024. Baixar do site da Broadcom:

<https://techdocs.broadcom.com/us/en/vmware-cis/desktop-hypervisors/workstation-pro.html>

A instalação do `.bundle` exige `sudo`:

```bash
sudo sh VMware-Workstation-Full-*.bundle
```

Aceitar EULA. Selecionar "Personal Use" quando perguntado. Depois validar:

```bash
which vmware vmrun vmware-vdiskmanager vmware-networks vmware-modconfig
# deve retornar os 5 caminhos em /usr/bin
sudo vmware-modconfig --console --install-all
# compila e instala os módulos do kernel
```

Se a compilação falhar (comum em Ubuntu com kernel novo), consultar a comunidade do Workstation Pro ou aplicar *patches* não-oficiais como `mkubecek/vmware-host-modules`.

### 3. Ferramentas Python (certipy e netexec)

Em distros recentes (Ubuntu 24+, Debian 12+, Kali), `pip install` global é bloqueado por PEP 668. Usar `pipx`:

```bash
pipx ensurepath
pipx install certipy-ad
pipx install netexec
# fechar e reabrir o terminal para o PATH atualizar
which certipy netexec
# deve retornar ~/.local/bin/...
```

Validação:

```bash
certipy --version  # esperado: 5.0.4 ou superior
netexec --version  # esperado: rolling
```

### 4. Checklist final antes de seguir para a Fase 1

```bash
# Cada comando abaixo deve retornar um caminho, sem erro:
which vmware vmrun vmware-vdiskmanager vmware-networks vmware-modconfig
which genisoimage certipy netexec python3

# Módulos VMware carregados no kernel:
lsmod | grep -E "vmnet|vmmon"
# esperado: ambos listados

# Estado da rede VMware:
sudo vmware-networks --status
# esperado: "All the services configured on all the networks are running"
```

Se algo falhar, resolver antes de continuar. O resto da automação (`gen-vmx.sh`, scripts PowerShell, scripts de ataque) assume que estes pré-requisitos estão atendidos.

## Estrutura

```
lab-repo/
├── 00-prereqs/           # Rede host-only
├── 01-autounattend/      # Geração dos Autounattend.xml + ISOs seed
├── 02-vmx/               # Geração dos descritores .vmx
├── 03-windows/           # Provisionamento dos roles (PowerShell)
├── 04-ataque/            # Reprodução de ESC1 e ESC2
├── iso/                  # ISOs Windows (gitignored, baixar manualmente)
├── vmware/               # VMs (gitignored, criado pelo gen-vmx.sh)
└── evidencias/           # Logs e PFXs dos ataques (gitignored)
```

## Ordem de execução

### Fase 1, preparação no host Kali

```bash
# 1. Criar a rede host-only vmnet10
sudo ./00-prereqs/criar-vmnet10.sh
# O host recebe automaticamente 10.10.10.1/24 na vmnet10 (VMware faz por conta).

# 2. Gerar os 3 Autounattend.xml e empacotá-los em ISOs seed
./01-autounattend/gen-autounattend.sh

# 3. Gerar os 3 descritores .vmx + VMDKs (exige ISOs Windows em iso/)
./02-vmx/gen-vmx.sh

# 4. Subir as 3 VMs (boot + instalação Windows desatendida, ~20 min)
vmrun -T ws start vmware/DC01/DC01.vmx nogui
vmrun -T ws start vmware/CA01/CA01.vmx nogui
vmrun -T ws start vmware/WS01/WS01.vmx nogui
```

Aguardar o autounattend concluir em cada VM. O sinal de pronto é o arquivo
`C:\setup-complete.flag` (criado pela última *FirstLogonCommand*). Como o
*OpenSSH FoD* não instala em rede *host-only* (vai falhar silenciosamente),
a interação remota usa WinRM (porta 5985), já habilitado por padrão no
Windows Server.

### Fase 2, configuração do domínio (executar do host Kali via netexec)

Os scripts PowerShell são enviados por WinRM via `powershell -EncodedCommand <base64>`. O método `$(cat script.ps1)` quebra com variáveis PowerShell (o bash expande `$X` antes), então usamos base64 UTF-16LE:

```bash
run_ps() {  # uso: run_ps <ip> <script.ps1>
    local enc
    enc=$(python3 -c "import base64; print(base64.b64encode(open('$2','rb').read().decode().encode('utf-16-le')).decode())")
    netexec winrm "$1" -u Administrator -p 'Lab@TCC2026' -X "powershell -EncodedCommand $enc"
}

# 1. Promover DC01 a primeiro Domain Controller (a VM reinicia)
run_ps 10.10.10.10 03-windows/01-promover-dc.ps1

# 2. Criar usuário/grupo + configurar KDC para aceitar PKINIT legacy
run_ps 10.10.10.10 03-windows/02-criar-usuarios.ps1

# 3. Ingressar CA01 e WS01 no domínio (cada VM reinicia)
run_ps 10.10.10.11 03-windows/03-ingressar-dominio.ps1
run_ps 10.10.10.20 03-windows/03-ingressar-dominio.ps1

# 4. Instalar AD CS em CA01 como Enterprise Root CA
run_ps 10.10.10.11 03-windows/04-instalar-ca.ps1

# 5. Criar e publicar os templates vulneráveis ESC1_TCC e ESC2_TCC
run_ps 10.10.10.11 03-windows/05-criar-templates-vulneraveis.ps1
```

Ponto de checkpoint sugerido (snapshot `vuln-templates-ready`):

```bash
vmrun -T ws snapshot vmware/DC01/DC01.vmx vuln-templates-ready
vmrun -T ws snapshot vmware/CA01/CA01.vmx vuln-templates-ready
```

### Fase 3, reprodução dos ataques

```bash
./04-ataque/esc1.sh
./04-ataque/esc2.sh
```

Cada script salva os logs e os artefatos (certificados PFX, *ccache* Kerberos,
*hash* NT extraído) em `evidencias/esc1/` ou `evidencias/esc2/`. O critério de
sucesso é a listagem de `Domain Admins`, `Schema Admins` e `Enterprise Admins`
no `whoami /groups` da última etapa.

## Decisões de design notáveis

| Decisão | Motivo |
|---------|--------|
| Firmware BIOS legacy, layout MBR | EFI default do Workstation 25 reporta "No Media" em qualquer ISO |
| Disco e CDs em SATA único | SCSI/lsisas1068 esgota slots PCIe; SATA evita SIGSEGV silencioso |
| `usb.present = FALSE` + `pciBridge4-7` extras | UEFI default tem poucos slots PCIe secundários |
| WinRM em vez de SSH | OpenSSH FoD não instala em rede *host-only*; WinRM já vem habilitado |
| Apenas Enterprise Root CA (sem hierarquia) | Escopo do TCC, todos os componentes necessários a ESC1/ESC2 estão presentes |

## Configurações de plataforma aplicadas (modo lab, reduzem segurança)

Para que ESC1/ESC2 via PKINIT funcionem num Windows Server 2022 limpo (com patches recentes), o script `02-criar-usuarios.ps1` aplica quatro mudanças no controlador de domínio. Em produção, manter os defaults é a **mitigação correta** discutida no Capítulo 6 do TCC.

| Configuração | Valor | Por quê |
|---|---|---|
| `StrongCertificateBindingEnforcement` | `0` (Disabled) | Permite mapeamento implícito por UPN no SAN (caminho de ESC1/ESC2). Default `2` (Full Enforcement) rejeita. |
| `CertificateMappingMethods` | `0x1F` | Aceita todos os 5 métodos legados, incluindo UPN. Default `0x18` aceita só strong mapping. |
| `dSHeuristics` 7º char | `2` | Permite LDAP bind anonymous nos containers de PKI. Sem isso o KDC não consegue baixar CRL via `ldap:///` e PKINIT falha com `CRYPT_E_REVOCATION_OFFLINE`. |
| Cert do DC em `LocalMachine\My` | Autoenroll do template Computer | Sem cert próprio, o KDC responde `KDC_ERR_PADATA_TYPE_NOSUPP` em qualquer AS-REQ via PKINIT. |

Templates ESC1_TCC e ESC2_TCC precisam ter `msPKI-Cert-Template-OID` único (gerado pelo script). Sem isso o CertSvc loga `ERROR_NOT_FOUND` e `certipy req` recebe `CERTSRV_E_UNSUPPORTED_CERT_TYPE`.

## Restauração entre execuções

Para repetir os ataques com logs limpos:

```bash
vmrun -T ws revertToSnapshot vmware/DC01/DC01.vmx vuln-templates-ready
vmrun -T ws revertToSnapshot vmware/CA01/CA01.vmx vuln-templates-ready
vmrun -T ws start vmware/DC01/DC01.vmx nogui
vmrun -T ws start vmware/CA01/CA01.vmx nogui
```

## Aviso

Este laboratório foi construído para fins acadêmicos, sobre infraestrutura
isolada do autor, sem qualquer rota para redes externas. Os *templates*
configurados são deliberadamente vulneráveis e **não devem** ser replicados em
ambientes de produção. As técnicas reproduzidas só devem ser usadas em
ambientes próprios ou com autorização formal.
