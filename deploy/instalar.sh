#!/usr/bin/env bash
# Instala el Centro 911 en una VM Ubuntu/Debian (AWS Academy, Corellium o local).
# Uso (desde la carpeta del proyecto):   bash deploy/instalar.sh
set -euo pipefail

echo "==> 1/5 Instalando Erlang/OTP y herramientas"
sudo apt-get update -qq
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
  erlang-nox erlang-dev erlang-eunit erlang-tools erlang-src git curl build-essential

OTP=$(erl -noshell -eval 'io:format("~s",[erlang:system_info(otp_release)]),halt().')
echo "    Erlang/OTP $OTP instalado"

echo "==> 2/5 Instalando rebar3"
if [ "$OTP" -ge 26 ]; then V=3.24.0; else V=3.22.1; fi
sudo curl -fsSL -o /usr/local/bin/rebar3 "https://github.com/erlang/rebar3/releases/download/$V/rebar3"
sudo chmod +x /usr/local/bin/rebar3
rebar3 version

echo "==> 3/5 Compilando y corriendo pruebas"
rebar3 compile
rebar3 eunit

echo "==> 4/5 Armando el release"
rebar3 release

echo "==> 5/5 Instalando como servicio systemd en /opt/centro911"
sudo systemctl stop centro911 2>/dev/null || true
sudo id centro911 >/dev/null 2>&1 || \
  sudo useradd --system --home /opt/centro911 --shell /usr/sbin/nologin centro911
sudo mkdir -p /opt/centro911
sudo cp -r _build/default/rel/p67_centro_de_emergencias_911/. /opt/centro911/
sudo chown -R centro911:centro911 /opt/centro911
sudo cp deploy/centro911.service /etc/systemd/system/centro911.service
sudo systemctl daemon-reload
sudo systemctl enable --now centro911

sleep 4
if curl -fs http://localhost:8080/api/estadisticas >/dev/null; then
  IP=$(curl -fs --max-time 2 http://checkip.amazonaws.com || hostname -I | awk '{print $1}')
  echo ""
  echo "LISTO. Abre en tu navegador:  http://$IP:8080"
else
  echo "El servicio no responde. Revisa:  sudo journalctl -u centro911 -n 50"
  exit 1
fi
