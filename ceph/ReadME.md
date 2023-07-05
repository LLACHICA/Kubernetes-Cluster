Install Dashboard

https://github.com/LLACHICA/Kubernetes-Cluster.git
ceph mgr module enable dashboard
ceph dashboard create-self-signed-cert

echo MyPassword1 > password.txt

ceph dashboard ac-user-create <name> -i password.txt adminstrator

ceph mgr module disable dashboard
ceph mgr module enable dashboard