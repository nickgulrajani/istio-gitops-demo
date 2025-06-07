#!/bin/bash

set -e

# Configurable
APP_NAME="istio-bookinfo"
NAMESPACE="argocd"
PORT=8080
ARGOCD_URL="http://localhost:$PORT"
ARGOCD_USER="admin"
ARGOCD_PASS=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)

echo "🚀 Setting up Argo CD port forwarding in background..."
kubectl port-forward svc/argocd-server -n $NAMESPACE $PORT:443 > port-forward.log 2>&1 &
PORT_PID=$!
sleep 5

echo "🔐 Logging into Argo CD CLI..."
argocd login localhost:$PORT --insecure --username "$ARGOCD_USER" --password "$ARGOCD_PASS"

echo "🌐 Opening Argo CD UI..."
open "$ARGOCD_URL"

echo "🧠 Routing menu:"
select version in "v1" "v2" "v3" "Quit"; do
  case $version in
    v1|v2|v3)
      echo "⚙️  Updating VirtualService for reviews to $version..."
      cat > traffic-split/virtual-service-reviews.yaml <<EOF
apiVersion: networking.istio.io/v1alpha3
kind: VirtualService
metadata:
  name: reviews
  namespace: default
spec:
  hosts:
    - reviews
  gateways:
    - bookinfo-gateway
  http:
    - route:
        - destination:
            host: reviews
            subset: $version
          weight: 100
EOF

      git add .
      git commit -m "🔁 Routed reviews to $version"
      git push

      echo "🔁 Syncing $APP_NAME with Argo CD..."
      argocd app sync $APP_NAME

      echo "♻️ Restarting deployments..."
      kubectl rollout restart deployment reviews-v1 reviews-v2 reviews-v3 -n default

      echo "✅ Traffic now routed to 'reviews-$version'"
      break
      ;;
    Quit)
      break
      ;;
    *)
      echo "Invalid option."
      ;;
  esac
done

# Cleanup port forward
kill $PORT_PID

