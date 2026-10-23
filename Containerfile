# Welfare TIME のサイトを、Hugo の開発サーバー（hugo server）でコンテナから起動する。
# 動作の確認用で、本番の配信には使わない。
#
# イメージには道具（Python、Hugo、Node、just と依存パッケージ）だけを入れ、
# ソースは実行時にリポジトリをマウントして渡す。
#
#   docker build -f Containerfile -t welfare-time .
#   docker run --rm -p 1313:1313 -v "$PWD":/app -v /app/node_modules welfare-time
#   → http://localhost:1313/welfare-time/
#
# -v /app/node_modules は、イメージの中の node_modules を使うために必要。
# ホストの node_modules には、ホストの OS 用の Tailwind のバイナリが入っており、コンテナでは動かない。
#
# ホストのポートは 1313 のままにする。Hugo のライブリロードがこのポートにつなぐため、
# 別のポートに割り当てるとページの自動更新が動かない。
#
# 起動するたびに、リポジトリにある食堂のPDF（data/pdfs/）とキッチンカーのアーカイブ
# （data/kitchen_cars_past.json）からAPIとCSSを生成する。生成物はホストの static/ と data/ に
# 書き出される（どれも .gitignore の対象）。大学サイトやキッチンカーのページからの取得は行わない
# （取得には Playwright の Chromium が必要なため）。

# バージョンは毎朝の更新のワークフロー（.github/workflows/daily_update.yml）に合わせる。
# Debian bookworm の python3 は 3.11 で、ワークフローと同じになる。
FROM node:26-bookworm-slim

ARG HUGO_VERSION=0.119.0
ARG JUST_VERSION=1.40.0
ARG TARGETARCH

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl python3 python3-venv \
    && curl -fsSL -o /tmp/hugo.deb \
        "https://github.com/gohugoio/hugo/releases/download/v${HUGO_VERSION}/hugo_extended_${HUGO_VERSION}_linux-${TARGETARCH:-amd64}.deb" \
    && apt-get install -y --no-install-recommends /tmp/hugo.deb \
    && rm -rf /tmp/hugo.deb /var/lib/apt/lists/*

WORKDIR /app

# 依存パッケージだけを入れる。ソースは実行時にマウントするのでコピーしない。
# playwright は取得（fetch）にしか使わないので入れない。
COPY requirements.txt package.json package-lock.json ./
RUN python3 -m venv /opt/venv \
    && grep -v '^playwright' requirements.txt > /tmp/requirements.txt \
    && /opt/venv/bin/pip install --no-cache-dir -r /tmp/requirements.txt "rust-just==${JUST_VERSION}" \
    && npm ci
ENV PATH="/opt/venv/bin:${PATH}"

EXPOSE 1313

# 起動時にAPIとCSSを生成してから、開発サーバーを起動する。
# キッチンカーは取得しないので、raw.html がなければ出店のない空のファイルを置いて解析させる。
# 出店が0件のとき、generator はアーカイブに手を加えずにそのまま使う。
# ホストで取得した raw.html があれば、それを使う。
# --bind 0.0.0.0 は、コンテナの外から接続できるようにするため。
CMD ["sh", "-c", "mkdir -p data/kitchencars && touch data/kitchencars/raw.html && just PYTHON=python3 generate && just css && exec hugo server --bind 0.0.0.0 --port 1313"]
