ALB_URL=$(kubectl get ingress taskmanager-ingress -n taskmanager -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

echo $ALB_URL

for i in {1..10}; do curl http://$ALB_URL/api/v1/tasks; done

for i in {1..5}; do
  curl -X POST http://$ALB_URL/api/v1/tasks \
    -H 'Content-Type: application/json' \
    -d '{"title":"Tâche '$i'","priority":"MEDIUM"}'
done


for i in {1..20}; do curl http://$ALB_URL/api/v1/tasks/99999; done
