# Caddy → Traefik 전환 + Friend 앱 k8s 이전

## 사전 조건 (수동)

- [ ] DNS A 레코드: `argocd.kimsijun.com` → `124.111.89.70`
- [ ] DNS A 레코드 확인: `friend.kimsijun.com` → `124.111.89.70`
- [ ] 공유기 포트포워딩: 80, 443 → 192.168.0.46

---

## Phase 1: Traefik HTTPS 설정 + Caddy 제거

### Step 1-1: infra 레포 GitHub 등록 + root-app 적용

```bash
# 최초 1회: ArgoCD가 infra 레포를 바라보도록 등록
kubectl apply -f k8s/root-app.yaml

# Traefik 설정은 HelmChartConfig이므로 별도 apply 필요
kubectl apply -f k8s/traefik/helmchartconfig.yaml

# ArgoCD 인그레스도 argocd 네임스페이스에 별도 apply
kubectl apply -f k8s/argocd/ingress.yaml

# friend-external 임시 라우팅
kubectl apply -f k8s/apps/friend-external.yaml

# MySQL, Redis 서비스 등록
kubectl apply -f k8s/services/
```

### Step 1-2: Caddy 중지 → Traefik 전환

```bash
# 1. Caddy 중지
sudo systemctl stop caddy && sudo systemctl disable caddy

# 2. Traefik svclb 재시작 (80/443 포트 재바인딩)
kubectl rollout restart daemonset svclb-traefik -n kube-system

# 3. 재시작 확인
kubectl get pods -n kube-system -l app=svclb-traefik -w
```

### Phase 1 검증

```bash
curl -I https://friend.kimsijun.com
curl -I https://argocd.kimsijun.com
curl -I http://friend.kimsijun.com  # HTTPS 리다이렉트 확인
```

**NAT 헤어피닝 안 될 경우:**
```bash
echo "192.168.0.46 argocd.kimsijun.com friend.kimsijun.com" | sudo tee -a /etc/hosts
```

### Caddy 완전 제거 (검증 후)

```bash
sudo apt remove caddy
```

---

## Phase 2: Friend 앱 k8s 이전

### Step 2-1: friend-app 소스 준비 및 GitHub 푸시

prodesk에서 friend 앱 소스(index.js, package.json, family.png)를 friend-app 레포에 복사 후 push.

### Step 2-2: CI 빌드 확인

```bash
gh run list --repo sijunkim/friend-app
```

### Step 2-3: IngressRoute 서비스 전환

infra 레포에서 `k8s/apps/friend-external.yaml`의 IngressRoute 서비스를
`friend-external` → `friend-app`으로 변경 후 push.

### Step 2-4: 기존 systemd 서비스 중지

```bash
sudo systemctl stop friend-app && sudo systemctl disable friend-app
```

### Step 2-5: 임시 리소스 정리

infra 레포에서 `k8s/apps/friend-external.yaml` 삭제 후 push.

---

## Phase 2 검증

```bash
curl https://friend.kimsijun.com
kubectl logs -n prodesk -l app=friend-app
kubectl get app friend-app -n argocd
```
