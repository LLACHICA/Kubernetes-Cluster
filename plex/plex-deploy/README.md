 helm install  plex ./charts/kube-plex --namespace plex  --set claimToken="claim-Wiarq9oVLxxxxxx-" --set persistence.data.claimName="plex-pvc-data" --set persistence.transcode.enabled=true --set persistence.transcode.claimName="pvc-trans"