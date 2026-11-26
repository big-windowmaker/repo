#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# build-repo.sh - monta o repositório pacman assinado [big-wm].
#
# Uso: build-repo.sh <publicados> <novos> <saída>
#
#   <publicados>  pacotes (*.pkg.tar.zst + .sig) baixados do release atual;
#                 pode estar vazio (primeira publicação)
#   <novos>       artefatos de CI (fetch-package-artifacts.sh), em subpastas
#   <saída>       diretório vazio: pacotes, assinaturas, banco e manifesto
#
# Variáveis:
#   SIGNING_KEY        subchave de assinatura exportada (gpg
#                      --export-secret-subkeys), em base64
#   SIGNING_SUBKEY     impressão digital da subchave de assinatura
#   PUBLIC_KEY         chave pública (keys/big-wm.asc): as assinaturas dos
#                      pacotes já publicados são conferidas com ela
#   EXPECTED_PACKAGES  nomes que precisam estar no repositório
#
# Regras:
#   - de cada pacote fica uma versão só, a maior (vercmp). Empate: fica a
#     publicada (mesmos bytes, mesma assinatura);
#   - todo pacote publicado tem a assinatura conferida antes de ficar: um
#     anexo trocado no release interrompe a publicação;
#   - pacote novo é assinado aqui; o banco também (repo-add --sign);
#   - ':' (época) vira '_' no nome do arquivo: o GitHub troca ':' nos
#     anexos, e o banco precisa do nome exato.
#
# Roda num contêiner Manjaro sem rede (repo-add, vercmp, bsdtar, gpg).
set -euo pipefail

readonly REPO_NAME=big-wm

die() { printf 'build-repo.sh: erro: %s\n' "$*" >&2; exit 1; }

(($# == 3)) || die "uso: build-repo.sh <publicados> <novos> <saída>"
current=$1 new=$2 out=$3
for tool in repo-add vercmp bsdtar gpg sha256sum; do
    command -v "$tool" >/dev/null || die "$tool não encontrado"
done
[[ -n "${SIGNING_KEY:-}" ]] || die "SIGNING_KEY vazio"
[[ "${SIGNING_SUBKEY:-}" =~ ^[0-9A-F]{40}$ ]] || die "SIGNING_SUBKEY inválido"
[[ -s "${PUBLIC_KEY:-}" ]] || die "PUBLIC_KEY não encontrado"
mkdir -p "$out"
[[ -z "$(ls -A "$out")" ]] || die "o diretório de saída precisa estar vazio: $out"

GNUPGHOME=$(mktemp -d)
export GNUPGHOME
trap 'rm -rf "$GNUPGHOME"' EXIT
chmod 700 "$GNUPGHOME"
gpg --batch --quiet --import "$PUBLIC_KEY" 2>/dev/null
base64 -d <<<"$SIGNING_KEY" | gpg --batch --quiet --import 2>/dev/null
gpg --batch --list-secret-keys --with-colons "$SIGNING_SUBKEY" | grep -q '^ssb' \
    || die "a subchave $SIGNING_SUBKEY não está em SIGNING_KEY"

pkginfo_field() { # arquivo campo
    bsdtar -xOf "$1" .PKGINFO | awk -v k="$2" '$1 == k && $2 == "=" { sub(/^[^=]*= /, ""); print; exit }'
}

declare -A best_file=() best_ver=() best_from=()
consider() { # arquivo origem
    local file=$1 from=$2 name version arch
    name=$(pkginfo_field "$file" pkgname)
    version=$(pkginfo_field "$file" pkgver)
    arch=$(pkginfo_field "$file" arch)
    [[ "$name" =~ ^[a-z0-9@._+-]+$ ]] || die "${file##*/}: pkgname inválido: '$name'"
    [[ "$version" =~ ^([0-9]+:)?[A-Za-z0-9._+~]+-[0-9.]+$ ]] || die "${file##*/}: versão inválida: '$version'"
    case "$arch" in x86_64 | any) ;; *) die "${file##*/}: arquitetura não suportada: $arch" ;; esac
    if [[ -z "${best_ver[$name]:-}" ]] || (($(vercmp "$version" "${best_ver[$name]}") > 0)); then
        best_file[$name]=$file best_ver[$name]=$version best_from[$name]=$from
    fi
}

# Publicados primeiro (ganham no empate), cada um com a assinatura conferida.
while IFS= read -r -d '' pkg; do
    [[ -s "$pkg.sig" ]] || die "${pkg##*/}: publicado sem assinatura"
    gpg --batch --quiet --verify "$pkg.sig" "$pkg" 2>/dev/null \
        || die "${pkg##*/}: a assinatura publicada não confere"
    consider "$pkg" publicado
done < <(find "$current" -maxdepth 1 -type f -name '*.pkg.tar.zst' -print0 | sort -z)

while IFS= read -r -d '' pkg; do
    consider "$pkg" "${pkg#"$new"/}"
done < <(find "$new" -type f -name '*.pkg.tar.zst' -print0 | sort -z)

((${#best_file[@]} > 0)) || die "nenhum pacote"

missing=()
for name in ${EXPECTED_PACKAGES:-}; do
    [[ -n "${best_file[$name]:-}" ]] || missing+=("$name")
done
((${#missing[@]} == 0)) || die "pacotes esperados ausentes: ${missing[*]}"

manifest="$out/$REPO_NAME.manifest"
echo "# nome versão arquivo sha256 origem" >"$manifest"
for name in $(printf '%s\n' "${!best_file[@]}" | sort); do
    src=${best_file[$name]}
    file=${src##*/}
    file=${file//:/_}
    [[ "$file" =~ ^[A-Za-z0-9@._+-]+\.pkg\.tar\.zst$ ]] || die "nome de arquivo inesperado: $file"
    install -m 0644 "$src" "$out/$file"
    if [[ "${best_from[$name]}" == publicado ]]; then
        install -m 0644 "$src.sig" "$out/$file.sig"
    else
        gpg --batch --quiet --no-armor --local-user "${SIGNING_SUBKEY}!" \
            --detach-sign --output "$out/$file.sig" "$out/$file"
    fi
    printf '%s %s %s %s %s\n' "$name" "${best_ver[$name]}" "$file" \
        "$(sha256sum "$out/$file" | cut -d' ' -f1)" "${best_from[$name]}" >>"$manifest"
done

(cd "$out" && repo-add --quiet --verify --sign --key "${SIGNING_SUBKEY}!" \
    "$REPO_NAME.db.tar.gz" ./*.pkg.tar.zst)

# repo-add cria big-wm.db/.files (e as .sig) como links simbólicos; anexos
# de release não têm links, então viram cópias.
for link in "$out/$REPO_NAME".{db,files}{,.sig}; do
    [[ -L "$link" ]] && cp --remove-destination "$(readlink -f "$link")" "$link"
done
for f in "$out/$REPO_NAME".{db,files}; do
    gpg --batch --quiet --verify "$f.sig" "$f" 2>/dev/null || die "${f##*/}: assinatura do banco não confere"
done

echo "==> [$REPO_NAME]: ${#best_file[@]} pacote(s)"
grep -v '^#' "$manifest" | awk '{ printf "    %-32s %-28s %s\n", $1, $2, $5 }'
