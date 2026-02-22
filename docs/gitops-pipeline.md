# GitOps Pipeline

## Overview

infra 레포는 ArgoCD App of Apps 패턴으로 prodesk k3s 클러스터의 모든 배포를 관리한다.
변경 경로는 두 가지로 나뉜다:

1. **인프라 변경** — infra 레포 push → ArgoCD가 매니페스트 변경 감지 → 자동 Sync
2. **앱 코드 변경** — 앱 레포 push → CI가 이미지 빌드 → Image Updater가 감지 → ArgoCD Sync

## 1. 인프라 변경 흐름

Deployment 리소스 조정, 인그레스 추가, 서비스 변경 등 k8s 매니페스트 수정 시.

```mermaid
sequenceDiagram
    actor Dev as Developer (MacBook)
    participant GH as GitHub<br/>sijunkim/infra
    participant Argo as ArgoCD<br/>(prodesk k3s)
    participant K3s as k3s Cluster<br/>(prodesk)

    Note over Dev,K3s: App of Apps 구조

    Note right of Argo: root-app이 감시 중:<br/>infra/k8s/argocd/apps/*.yaml<br/><br/>각 Application이 감시 중:<br/>infra/k8s/apps/{앱이름}/

    Dev->>GH: git push origin master<br/>(매니페스트 수정)

    Note over Dev,K3s: ArgoCD 자동 감지 및 Sync

    loop 3분마다 폴링
        Argo->>GH: Git 레포 변경 확인<br/>targetRevision: master
        GH-->>Argo: 최신 커밋 반환
    end

    Argo->>Argo: 변경 감지<br/>Live 상태 ≠ Git 상태<br/>→ OutOfSync

    Argo->>K3s: 자동 Sync (automated)<br/>kubectl apply 매니페스트
    K3s->>K3s: 리소스 반영<br/>Deployment/Service/Ingress 등

    Argo->>Argo: 상태 변경: Synced + Healthy

    Note over Dev,K3s: selfHeal: true → 수동 변경도 자동 복구
```

### 핵심 동작 원리

ArgoCD는 prodesk k3s 내부에서 실행되며 **3분마다 Git 레포를 폴링**한다.
infra 레포에 push가 발생하면:

1. ArgoCD가 Git의 매니페스트와 클러스터의 Live 상태를 비교
2. 차이가 있으면 **OutOfSync** 상태로 전환
3. `syncPolicy.automated`가 설정되어 있으므로 **자동으로 kubectl apply** 실행
4. 클러스터에 변경 반영 후 **Synced + Healthy** 상태로 전환

`selfHeal: true` 설정으로, 누군가 kubectl로 직접 수정해도 Git 상태로 자동 복구된다.

## 2. 앱 코드 변경 흐름

비즈니스 로직 수정, 버그 수정 등 앱 소스 코드 변경 시.

```mermaid
sequenceDiagram
    actor Dev as Developer (MacBook)
    participant App as GitHub<br/>sijunkim/{앱 레포}
    participant CI as GitHub Actions<br/>CI Runner (ubuntu)
    participant GHCR as GitHub Container Registry<br/>ghcr.io/sijunkim/{앱}
    participant IU as ArgoCD Image Updater<br/>(prodesk k3s)
    participant Argo as ArgoCD<br/>(prodesk k3s)
    participant K3s as k3s Cluster<br/>(prodesk)

    Note over Dev,K3s: 1. CI — 이미지 빌드

    Dev->>App: git push origin master
    App->>CI: push 이벤트 트리거
    activate CI
    CI->>CI: Docker 빌드
    CI->>GHCR: docker push<br/>{앱}:master-{sha}
    deactivate CI

    Note over Dev,K3s: 2. CD — 이미지 감지

    loop 2분마다 폴링
        IU->>GHCR: 새 이미지 태그 조회<br/>regexp: ^master-
        GHCR-->>IU: 태그 목록 반환
    end

    IU->>IU: 새 이미지 감지
    IU->>Argo: 이미지 오버라이드 저장<br/>(write-back-method: argocd)<br/>infra 레포에 커밋 없음

    Note over Dev,K3s: 3. 배포

    Argo->>K3s: Sync — Deployment 이미지 태그 변경
    K3s->>GHCR: docker pull 새 이미지
    K3s->>K3s: Rolling Update<br/>기존 Pod 종료 → 새 Pod 생성
    Argo->>Argo: Synced + Healthy
```

### write-back-method: argocd

Image Updater가 새 이미지를 감지해도 **infra 레포에 커밋을 남기지 않는다.**
대신 ArgoCD 내부에 이미지 오버라이드를 저장한다:

```
infra 레포 (Git):     image: ghcr.io/sijunkim/naver-news-spring:master-placeholder
ArgoCD 오버라이드:     image: ghcr.io/sijunkim/naver-news-spring:master-484af0a  ← 실제 배포
```

이 덕분에:
- 앱 코드 push 시 infra 레포에 불필요한 커밋이 쌓이지 않음
- infra 레포는 인프라 변경 이력만 깔끔하게 유지됨

## App of Apps 구조

```
root-app (ArgoCD Application)
│  감시: infra/k8s/argocd/apps/
│
├── naver-news (Application)
│   감시: infra/k8s/apps/naver-news/
│   Image Updater: ghcr.io/sijunkim/naver-news-spring:master-*
│
├── friend-app (Application)
│   감시: infra/k8s/apps/friend-app/
│   Image Updater: ghcr.io/sijunkim/friend-app:master-*
│
└── mysql (Application)
    감시: infra/k8s/apps/mysql/
```

새 앱을 추가하려면:
1. `k8s/apps/{앱이름}/deployment.yaml` 작성
2. `k8s/argocd/apps/{앱이름}.yaml` 작성
3. git push → root-app이 자동 감지 → 새 Application 생성

## Component Details

| 구성 요소 | 위치 | 역할 |
|-----------|------|------|
| **root-app** | ArgoCD (prodesk) | `k8s/argocd/apps/` 감시, 하위 Application 자동 생성/삭제 |
| **ArgoCD** | prodesk k3s (argocd 네임스페이스) | Git 매니페스트 기반 배포 관리, 3분 폴링 |
| **Image Updater** | prodesk k3s (argocd 네임스페이스) | GHCR 2분 폴링, 새 이미지 감지 시 ArgoCD 오버라이드 |
| **Traefik** | prodesk k3s (kube-system) | HTTPS 인그레스, Let's Encrypt, IP 화이트리스트 |
| **k3s** | prodesk (192.168.0.46) | 컨테이너 실행 환경 |
| **GHCR** | ghcr.io/sijunkim/* | Docker 이미지 저장소 |

## Key Files

| 파일 | 용도 |
|------|------|
| `k8s/root-app.yaml` | App of Apps 루트 (최초 1회 kubectl apply) |
| `k8s/argocd/apps/*.yaml` | 각 앱의 ArgoCD Application 정의 |
| `k8s/apps/{앱}/deployment.yaml` | Deployment + Service 매니페스트 |
| `k8s/apps/{앱}/kustomization.yaml` | Kustomize 설정 (Image Updater 연동용) |
| `k8s/traefik/helmchartconfig.yaml` | Traefik ACME + HTTPS + externalTrafficPolicy |
| `k8s/argocd/ingress.yaml` | ArgoCD IngressRoute + IP 화이트리스트 |
| `k8s/services/*.yaml` | 공유 인프라 서비스 (Redis Endpoints 등) |
