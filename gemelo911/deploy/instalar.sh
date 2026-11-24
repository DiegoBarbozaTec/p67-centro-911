#!/usr/bin/env bash
# Instala el gemelo 911 (SWI-Prolog + Janus + matplotlib) en Ubuntu 24.04 (AWS ARM o x86)
# y lo deja como servicio en el puerto 8082.
# Uso (desde la carpeta gemelo911):   bash deploy/instalar.sh
set -euo pipefail

echo "==> 1/4 SWI-Prolog (PPA estable, trae Janus) y Python con matplotlib"
sudo apt-get update -qq
sudo apt-get install -y -qq software-properties-common curl
sudo apt-add-repository -y ppa:swi-prolog/stable
sudo apt-get update -qq
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq swi-prolog python3-matplotlib
swipl --version
swipl -g "use_module(library(janus)), py_call(sys:version, V), format('Janus OK, Python ~w~n', [V])" -t halt

echo "==> 2/4 Pruebas plunit"
swipl -g run_tests -t halt tests/reglas_tests.pl

echo "==> 3/4 Instalando en /opt/gemelo911 como servicio"
sudo mkdir -p /opt/gemelo911
sudo cp -r hechos.pl escenarios.pl reglas.pl explica.pl servidor.pl graficas.py gemelo.pl web /opt/gemelo911/
sudo id gemelo911 >/dev/null 2>&1 || sudo useradd --system --home /opt/gemelo911 --shell /usr/sbin/nologin gemelo911
sudo mkdir -p /opt/gemelo911/salida
sudo chown -R gemelo911:gemelo911 /opt/gemelo911
sudo cp deploy/gemelo911.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now gemelo911

echo "==> 4/4 Verificando"
sleep 4
curl -fs http://localhost:8082/api/estado >/dev/null && echo "API OK"
curl -fs -o /dev/null http://localhost:8082/grafica/mapa && echo "Gráfica de Python (Janus) OK"
IP=$(curl -fs --max-time 2 http://checkip.amazonaws.com || hostname -I | awk '{print $1}')
echo ""
echo "LISTO. Abre:  http://$IP:8082   (recuerda abrir el puerto 8082 en el grupo de seguridad)"
