# infra

prodesk 홈서버 인프라를 관리하는 레포지토리.
ArgoCD App of Apps 패턴으로 모든 k8s 리소스를 선언적으로 관리한다.

## 구조

```
k8s/
├── root-app.yaml                  # App of Apps 루트 (최초 1회 kubectl apply)
├── traefik/
│   └── helmchartconfig.yaml       # Traefik ACME + HTTPS 리다이렉트
├── argocd/
│   ├── ingress.yaml               # ArgoCD IngressRoute + IP 화이트리스트
│   └── apps/                      # ArgoCD Application 정의 (root-app이 감시)
│       ├── naver-news.yaml
│       └── friend-app.yaml
├── apps/                          # 앱 배포 매니페스트 (각 Application이 감시)
│   ├── naver-news/
│   │   ├── deployment.yaml
│   │   └── kustomization.yaml
│   ├── friend-app/
│   │   ├── deployment.yaml
│   │   └── kustomization.yaml
│   └── friend-external.yaml       # 임시: friend 앱 k8s 이전 전까지 사용
└── services/                      # 공유 인프라 서비스 (호스트 docker → k8s Endpoints)
    ├── mysql.yaml
    └── redis.yaml
```

## 운영 방식

| 변경 대상 | 행동 | 반영 경로 |
|-----------|------|-----------|
| 앱 코드 | 앱 레포 push | CI → 이미지 빌드 → Image Updater → ArgoCD Sync |
| 인프라 | infra 레포 push | ArgoCD root-app이 변경 감지 → 자동 Sync |

## 초기 설정

```bash
# 최초 1회만 실행
kubectl apply -f k8s/root-app.yaml
```

이후 모든 변경은 git push만으로 반영된다.
