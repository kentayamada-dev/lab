# タグではなく digest で固定する。タグは同じ名前のまま中身が変わりうるため、digest を付けないと
# 同じ Dockerfile から別のイメージが出来る。ワークフローのコンテナイメージも同じ理由で固定しており
# （.github/workflows/ci.yml）、Renovate も config:best-practices 経由の docker:pinDigests で
# この形を前提にしている（プリセットの extends に含まれることを確認。
# .github/renovate.json5 の pinDigest の節も参照）。タグは読みやすさのために残す。
# https://docs.renovatebot.com/docker/
#
# 値は manifest list（OCI image index）の digest で、linux/amd64 と linux/arm64/v8 の両方を含む
# （docker buildx imagetools inspect で確認）。アーキテクチャ別の digest を書くと片方でしか動かない。
FROM golang:1.27.1-trixie@sha256:3b77fc618ec235a1ab412de7737f120dd507c57e8d87de4cbb7994fb94275ed5

# 変数名を USERNAME ではなく DEV_USER にしているのは、hadolint の DL3064 が
# 「機密値の疑いがある名前」として username を部分一致・大文字小文字無視で検出し、
# CI の --failure-threshold style では warning でも失敗するため。
# 判定に使われる語は api_key / client_key / password / private / secret / token / username。
# https://github.com/hadolint/hadolint/blob/master/src/Hadolint/Rule/DL3064.hs
ARG DEV_USER=dev
ARG USER_UID=1000
ARG USER_GID=$USER_UID

# --shell を明示しているのは、省くと /etc/default/useradd の SHELL=/bin/sh が使われ、
# ログインシェルが dash（Debian の /bin/sh は dash へのリンク）になるため。dash は -m で置かれる
# /home/$DEV_USER/.bashrc を読まず、プロンプトも既定の "$ " だけになる。
# VS Code のターミナルはこのログインシェルを起動するので、そのままだと補完も色も効かない
# （trixie の /bin/sh が dash であること、その PS1 が "$ " であることは実測）。
# https://code.visualstudio.com/remote/advancedcontainers/add-nonroot-user
RUN groupadd --gid $USER_GID $DEV_USER \
  && useradd --uid $USER_UID --gid $USER_GID --shell /bin/bash -m $DEV_USER

# gopls は Go の公式の language server で、Go 拡張の補完・定義ジャンプ・診断・リファクタリングの
# 土台になっている。無い場合、拡張は legacy mode に落ちて機能の多くが使えなくなる。
# https://github.com/golang/vscode-go/blob/master/docs/tools.md
#
# 整形と静的解析も gopls に寄せている（設定は devcontainer.json の gopls.formatting.gofumpt と
# gopls.ui.diagnostic.staticcheck）。gopls は gofumpt の整形と staticcheck の解析器一式を
# 内蔵しており、別途バイナリを置く必要がない。そのため gofumpt と staticcheck は入れていない。
# https://github.com/golang/vscode-go/blob/master/docs/settings.md
#
# 拡張は欠けているツールを自分で入れようとするが、入れ先は GOPATH/bin でコンテナの書き込み層に
# 当たるため再ビルドで消える。gopls は拡張の定義で isImportant: true なので、イメージに入れないと
# 再ビルドのたびに導入を促される。
# 既にあるツールを黙って差し替えることはない（go.toolsManagement.autoUpdate の既定は false）。
#
# 版は Renovate の customManagers:dockerfileVersions プリセットが追う
# （有効にしている理由と、素の ARG では追えない理由は .github/renovate.json5）。
# 直前の行がその指定で、depName と datasource を Renovate に渡す。44.95.0 の --dry-run=extract で
# datasource=go の依存として拾われることを実測した。
# プリセットが見るのは `<名前>_VERSION` という形の ARG なので、変数名は変えられない。
# renovate: datasource=go depName=golang.org/x/tools/gopls
ARG GOPLS_VERSION=v0.23.0

# go install の成果物は GOPATH/bin（/go/bin）に入る。golang イメージがそこを PATH に含めており、
# 権限も 1777 なので dev ユーザーからそのまま使える。home の下ではないため、
# /home/$DEV_USER にマウントが被ってもツールが隠れない（空のディレクトリを bind マウントして実測）。
#
# go clean はビルドキャッシュとモジュールキャッシュを消す。ここで入れるツールの分しか入っておらず、
# 利用者が使うものではない。付けないとイメージが 1.72GB、付けると 1.34GB になる（gofumpt と
# staticcheck を入れていた時点での実測）。
RUN go install "golang.org/x/tools/gopls@${GOPLS_VERSION}" \
  && go clean -cache -modcache

USER $DEV_USER
