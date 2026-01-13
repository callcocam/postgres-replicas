#!/bin/bash

# ============================================
# Script para importar dashboards no Grafana
# ============================================

set -e

GRAFANA_URL="${GRAFANA_URL:-http://localhost:3000}"
GRAFANA_USER="${GRAFANA_USER:-admin}"
GRAFANA_PASSWORD="${GRAFANA_PASSWORD:-plannerate2026}"

# Dashboard IDs to import
DASHBOARDS=(
  1860   # Node Exporter for Prometheus
  9628   # Prometheus 
  16396  # Prometheus Query
  763    # Redis
  193    # PostgreSQL
)

echo "🚀 Iniciando importação de dashboards do Grafana..."
echo "📍 URL: $GRAFANA_URL"
echo "👤 Usuário: $GRAFANA_USER"
echo ""

# Get API token via basic auth
echo "🔐 Autenticando no Grafana..."
API_TOKEN=$(curl -s -X POST "$GRAFANA_URL/api/auth/login" \
  -H "Content-Type: application/json" \
  -d "{\"user\":\"$GRAFANA_USER\",\"password\":\"$GRAFANA_PASSWORD\"}" | jq -r '.token')

if [ -z "$API_TOKEN" ] || [ "$API_TOKEN" = "null" ]; then
  echo "❌ Erro: Não foi possível autenticar no Grafana"
  exit 1
fi

echo "✅ Autenticado com sucesso!"
echo ""

# Import each dashboard
for DASHBOARD_ID in "${DASHBOARDS[@]}"; do
  echo "📊 Importando dashboard ID: $DASHBOARD_ID..."
  
  # Download dashboard from Grafana.com
  DASHBOARD_JSON=$(curl -s "https://grafana.com/api/dashboards/$DASHBOARD_ID/revisions/1/download")
  
  if echo "$DASHBOARD_JSON" | jq . > /dev/null 2>&1; then
    # Import to local Grafana
    RESPONSE=$(curl -s -X POST "$GRAFANA_URL/api/dashboards/db" \
      -H "Authorization: Bearer $API_TOKEN" \
      -H "Content-Type: application/json" \
      -d "{\"dashboard\": $DASHBOARD_JSON, \"overwrite\": true}")
    
    # Check response
    if echo "$RESPONSE" | jq . > /dev/null 2>&1; then
      STATUS=$(echo "$RESPONSE" | jq -r '.status // .message // "unknown"')
      ID=$(echo "$RESPONSE" | jq -r '.id // "N/A"')
      
      if [ "$STATUS" = "success" ] || [ "$ID" != "N/A" ]; then
        echo "✅ Dashboard $DASHBOARD_ID importado com sucesso (ID: $ID)"
      else
        echo "⚠️  Dashboard $DASHBOARD_ID: $STATUS"
      fi
    else
      echo "❌ Erro ao importar dashboard $DASHBOARD_ID"
    fi
  else
    echo "⚠️  Não foi possível baixar dashboard $DASHBOARD_ID"
  fi
  
  echo ""
done

echo "🎉 Importação concluída!"
echo ""
echo "📈 Dashboards disponíveis em:"
echo "   https://grafana.plannerate.dev.br/dashboards"
