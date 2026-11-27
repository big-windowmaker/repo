# [big-wm] — repositório de pacotes do Big WindowMaker

Repositório pacman **assinado** com todos os pacotes do Big WindowMaker:
sessões X11 e Wayland, Window Maker, wlmaker, dockapps, temas, tela de login,
zonas e ferramentas. Com ele, uma correção chega a quem já instalou pelo
`pacman -Syu`, sem reinstalar a ISO.

A ISO do Big WindowMaker já vem com o repositório ativado. Os passos abaixo
são para um sistema instalado antes disso, ou para quem quer o Big
WindowMaker num BigLinux/BigCommunity.

## Ativar

1. Confie na chave do repositório. Confira a impressão digital antes de
   assinar; ela também está no `big-wm-keyring` e no
   [`packages`](https://github.com/big-windowmaker/packages/tree/main/big-wm-keyring).

   ```sh
   curl -fsSLO https://raw.githubusercontent.com/big-windowmaker/repo/main/keys/big-wm.asc
   gpg --show-keys big-wm.asc      # 2F36 D64F 633B BA80 052F  4893 4AF5 FC29 61C2 E4AF
   sudo pacman-key --add big-wm.asc
   sudo pacman-key --lsign-key 2F36D64F633BBA80052F48934AF5FC2961C2E4AF
   ```

2. Em `/etc/pacman.conf`, **antes** do primeiro repositório (`[core]`, ou
   `[biglinux-priority]` no BigLinux), acrescente:

   ```ini
   [big-wm]
   SigLevel = Required
   Server = https://github.com/big-windowmaker/repo/releases/download/$arch
   ```

   Antes dos outros porque, quando um pacote existe em dois repositórios
   (o `windowmaker`, por exemplo), o pacman usa o primeiro.

3. Se o seu `/etc/pacman.conf` tem `IgnorePkg = windowmaker` (ISOs antigas
   do Big WindowMaker), apague essa linha. O `windowmaker` do Big
   WindowMaker agora tem `epoch=1`, e o do repositório da distribuição não
   o substitui mais.

4. Atualize e instale o chaveiro, que passa a manter a chave em dia:

   ```sh
   sudo pacman -Syu big-wm-keyring
   ```

## Como funciona

- Os pacotes são compilados pela CI de cada repositório da organização
  ([packages](https://github.com/big-windowmaker/packages),
  [big-wm](https://github.com/big-windowmaker/big-wm) e outros), num
  contêiner Manjaro limpo, só depois do merge no `main`.
- O workflow [`publicar`](.github/workflows/publicar.yml) roda a cada 6 horas
  (e sob demanda). Ele junta o que já está publicado com os artefatos novos,
  fica com a maior versão de cada pacote, confere a assinatura de tudo o que
  já estava publicado, assina o que é novo e o banco (num contêiner sem
  rede, [`scripts/build-repo.sh`](scripts/build-repo.sh)), e só então
  substitui os anexos do release
  [`x86_64`](https://github.com/big-windowmaker/repo/releases/tag/x86_64).
  O `big-wm.manifest` lista nome, versão, arquivo e sha256 de cada pacote.
- Depois de publicar, um segundo job faz o caminho de um usuário num Manjaro
  limpo: confia na chave, sincroniza, instala e confere que um pacote
  adulterado é recusado.

## A chave

| | Impressão digital | Validade | Onde fica |
| --- | --- | --- | --- |
| Primária (só certifica) | `2F36 D64F 633B BA80 052F  4893 4AF5 FC29 61C2 E4AF` | 2031-11-25 | offline, com o mantenedor |
| Subchave de assinatura | `2C5B E454 0995 63AB 4C78  3205 173E 2C09 FC18 33B0` | 2028-11-25 | segredo `REPO_SIGNING_KEY`; o job que assina roda no ambiente `repo-assinatura`, que só aceita o `main` |

Se a subchave vazar ou expirar, ela é revogada ou trocada com a chave
primária, e o `big-wm-keyring` é atualizado. Quem já confia na chave primária
não precisa fazer nada.

Falhas de segurança: veja [SECURITY.md](https://github.com/big-windowmaker/.github/blob/main/SECURITY.md).

## Licença

Scripts sob GPL-3.0-or-later ([LICENSE](LICENSE)). Cada pacote tem a sua
própria licença.
