# SOPS + Age + KSOPS 설정 가이드

## 개념 설명

### SOPS — Secrets OPerationS

Mozilla에서 개발한 **파일 암호화 도구**. YAML, JSON, ENV, INI 파일의 **값(value)만 암호화**하고 키(key)는 평문으로 유지한다.

```yaml
# 일반 base64 Secret (사실상 평문 — 누구나 디코딩 가능)
stringData:
  DB_PASSWORD: "c3VwZXJzZWNyZXQ="   # echo c3VwZXJzZWNyZXQ= | base64 -d → supersecret

# SOPS 암호화 Secret (실제 암호화 — 키 없이는 복호화 불가)
stringData:
  DB_PASSWORD: ENC[AES256_GCM,data:vHmvb2qCl+GU,iv:vkvg5I...,tag:scgff...,type:str]
```

**핵심 특징:**
- 키 이름은 보이지만 값은 AES-256-GCM(Advanced Encryption Standard 256-bit, Galois/Counter Mode)으로 암호화 → Git diff에서 "어떤 필드가 변경됐는지"는 보이지만 값은 노출되지 않음
- `sops secret.enc.yaml` 명령으로 편집하면 자동으로 복호화 → `$EDITOR`로 편집 → 저장 시 자동 암호화
- AWS KMS(Key Management Service), GCP KMS, Azure Key Vault, PGP(Pretty Good Privacy), **age** 등 다양한 암호화 백엔드 지원

### Age — Actually Good Encryption

Daniel J. Bernstein의 암호학 설계를 기반으로 한 **현대적 파일 암호화 도구**. PGP(Pretty Good Privacy)/GPG(GNU Privacy Guard)의 대안으로 설계되었다.

```
# 키 생성 (한 번만 실행)
$ age-keygen -o keys.txt
Public key: age1pkq2sx0xg0sjpr57t9yqtar5sg255fafhah9kdc5luh738xzk9psc4pkkl

# keys.txt 내용
# created: 2026-03-08T13:12:08+09:00
# public key: age1pkq2sx0xg0sjpr57t9yqtar5sg255fafhah9kdc5luh738xzk9psc4pkkl
AGE-SECRET-KEY-1XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
```

**PGP 대비 age의 장점:**
| 항목 | PGP/GPG | age |
|------|---------|-----|
| 키 생성 | `gpg --full-generate-key` (이름, 이메일, 만료일 등 입력) | `age-keygen` (1줄) |
| 키 크기 | 공개키 블록 수십 줄 | 공개키 1줄 (59자) |
| 키 관리 | keyring, trust model, subkey | 파일 1개 (`keys.txt`) |
| 알고리즘 | RSA/DSA(Digital Signature Algorithm)/ECDSA(Elliptic Curve DSA) (선택 필요) | X25519(Elliptic Curve Diffie-Hellman) + ChaCha20-Poly1305 (고정) |

**이 프로젝트에서의 역할:**
- SOPS의 암호화 백엔드로 사용
- 공개키(`age1...`)는 `.sops.yaml`에 저장 → 암호화에 사용 (노출 가능)
- 비공개키(`AGE-SECRET-KEY-...`)는 `~/.config/sops/age/keys.txt`에 보관 → 복호화에 사용 (**절대 Git에 커밋하지 않음**)

### KSOPS — Kustomize Secret OPerationS

**Kustomize의 exec 플러그인**으로, Kustomize 빌드 시 SOPS 암호화된 파일을 자동으로 복호화한다.

- **Kustomize**: Kubernetes 매니페스트를 패치/오버레이 방식으로 관리하는 도구. `kubectl`에 내장되어 있다.
- **exec 플러그인**: Kustomize가 빌드 시 외부 바이너리를 실행하여 결과를 매니페스트에 포함시키는 확장 메커니즘

ArgoCD는 내부적으로 Kustomize를 사용하여 매니페스트를 빌드하므로, KSOPS를 통해 암호화된 Secret을 복호화 → 클러스터에 적용하는 파이프라인이 완성된다.

### 전체 흐름

```
개발자 로컬                          Git (GitHub)                    ArgoCD (클러스터)
─────────────                     ──────────────                  ──────────────────

secret.yaml (평문)
     │
     ▼
sops --encrypt
     │
     ▼
secret.enc.yaml ──── git push ────→ secret.enc.yaml ────→ ArgoCD repo-server
(암호화된 상태)                    (암호화된 상태)              │
                                                              ▼
                                                         KSOPS 복호화
                                                         (age 비공개키 사용)
                                                              │
                                                              ▼
                                                         K8s Secret 생성
                                                         (클러스터 내부에만 평문 존재)
```

> [!IMPORTANT]
> **평문이 존재하는 곳**: 개발자 로컬 (편집 시 잠깐) + 클러스터 내부 (Secret 오브젝트)
> **암호화 상태인 곳**: Git 레포지토리 (항상)

### 이 방식을 선택한 이유

| 기준 | SOPS + Age | SealedSecrets | ESO (External Secrets Operator) |
|------|-----------|--------------|----------------------|
| 외부 의존성 | 없음 | 클러스터 내 controller | AWS/GCP/Vault 필요 |
| 로컬 편집 | `sops file.yaml`으로 즉시 편집 | 클러스터 접속 필요 (kubeseal) | 외부 저장소 접속 필요 |
| Git 이력 | 변경된 필드 추적 가능 | 전체 blob 변경 | Secret 값 자체는 Git에 없음 |
| 클러스터 재구축 | age 키 1개만 있으면 복원 | controller 비공개키 필요 | 외부 저장소가 살아있으면 OK |
| 홈 서버 적합도 | 적합 | 적합 | 오버엔지니어링 |

---

## 설치 및 설정

### 사전 준비 (로컬 Mac — 완료)

```bash
# sops, age 설치
brew install sops age

# age 키 생성
age-keygen -o ~/.config/sops/age/keys.txt

# .sops.yaml (레포 루트에 생성 완료)
# secret*.yaml 파일의 data/stringData 필드만 암호화
```

### prodesk에서 실행할 작업

#### 1. age 비공개키를 ArgoCD에 등록

```bash
# 맥북에서 age 비공개키를 prodesk로 복사
scp ~/.config/sops/age/keys.txt prodesk:/tmp/keys.txt

# prodesk에서 실행
sudo kubectl -n argocd create secret generic age-key \
  --from-file=keys.txt=/tmp/keys.txt
rm /tmp/keys.txt
```

#### 2. ArgoCD repo-server에 KSOPS 설정

ArgoCD repo-server가 SOPS 복호화를 수행하도록 패치:

```bash
# KSOPS 설치를 위한 initContainer + age 키 마운트
sudo kubectl -n argocd patch deployment argocd-repo-server --type='json' -p='[
  {
    "op": "add",
    "path": "/spec/template/spec/initContainers/-",
    "value": {
      "name": "install-ksops",
      "image": "viaductoss/ksops:v4.3.2",
      "command": ["sh", "-c", "cp /usr/local/bin/kustomize-sops /custom-tools/"],
      "volumeMounts": [{"name": "custom-tools", "mountPath": "/custom-tools"}]
    }
  },
  {
    "op": "add",
    "path": "/spec/template/spec/containers/0/env/-",
    "value": {"name": "SOPS_AGE_KEY_FILE", "value": "/age-key/keys.txt"}
  },
  {
    "op": "add",
    "path": "/spec/template/spec/containers/0/env/-",
    "value": {"name": "XDG_CONFIG_HOME", "value": "/.config"}
  },
  {
    "op": "add",
    "path": "/spec/template/spec/containers/0/volumeMounts/-",
    "value": {"name": "age-key", "mountPath": "/age-key", "readOnly": true}
  },
  {
    "op": "add",
    "path": "/spec/template/spec/containers/0/volumeMounts/-",
    "value": {"name": "custom-tools", "mountPath": "/usr/local/bin/kustomize-sops"}
  },
  {
    "op": "add",
    "path": "/spec/template/spec/volumes/-",
    "value": {"name": "age-key", "secret": {"secretName": "age-key"}}
  },
  {
    "op": "add",
    "path": "/spec/template/spec/volumes/-",
    "value": {"name": "custom-tools", "emptyDir": {}}
  }
]'
```

#### 3. ArgoCD ConfigMap(CM)에 Kustomize 플러그인 활성화

```bash
sudo kubectl -n argocd edit configmap argocd-cm
```

추가할 내용:

```yaml
data:
  kustomize.buildOptions: "--enable-alpha-plugins --enable-exec"
```

---

## Secret 실제 값 입력

현재 `secret.enc.yaml` 파일에는 `CHANGE_ME` placeholder가 암호화되어 있다.
prodesk 접속 가능할 때 기존 클러스터의 Secret에서 실제 값을 가져와 반영한다.

### 기존 Secret 값 확인

```bash
# mysql-secret
sudo kubectl -n prodesk get secret mysql-secret -o jsonpath='{.data}' | python3 -c "
import sys,json,base64
data = json.load(sys.stdin)
for k,v in data.items():
    print(f'{k}: {base64.b64decode(v).decode()}')"

# naver-news-secret
sudo kubectl -n prodesk get secret naver-news-secret -o jsonpath='{.data}' | python3 -c "
import sys,json,base64
data = json.load(sys.stdin)
for k,v in data.items():
    print(f'{k}: {base64.b64decode(v).decode()}')"
```

### SOPS로 편집

```bash
# sops 명령어로 열면 자동 복호화 → $EDITOR로 편집 → 저장 시 자동 암호화
sops k8s/apps/mysql/secret.enc.yaml
sops k8s/apps/naver-news/secret.enc.yaml
```

> [!TIP]
> `sops` 명령어는 `$EDITOR` 환경변수를 사용한다. `vim`, `nano`, `code --wait` 등 선호하는 에디터를 설정할 수 있다.
> ```bash
> export EDITOR="vim"  # ~/.zshrc에 추가
> ```

---

## 검증

```bash
# 1. 복호화 테스트 — 평문이 출력되면 성공
sops -d k8s/apps/mysql/secret.enc.yaml
sops -d k8s/apps/naver-news/secret.enc.yaml

# 2. Kustomize 빌드 테스트 — 모든 리소스가 출력되면 성공
kubectl kustomize k8s/apps/mysql/
kubectl kustomize k8s/apps/naver-news/
kubectl kustomize k8s/apps/friend-app/

# 3. ArgoCD Sync 후 Pod 정상 기동 확인
argocd app sync mysql
argocd app sync naver-news

# 4. 기존 Secret 값과 일치 확인
kubectl -n prodesk get secret mysql-secret -o yaml
kubectl -n prodesk get secret naver-news-secret -o yaml
```

---

## 일상 운영

### Secret 값 변경 시

```bash
# 1. SOPS로 편집 (자동 복호화 → 편집 → 자동 암호화)
sops k8s/apps/mysql/secret.enc.yaml

# 2. Git 커밋 & 푸시
git add k8s/apps/mysql/secret.enc.yaml
git commit -m "chore: update mysql secret"
git push

# 3. ArgoCD가 자동 Sync (selfHeal: true)
```

### age 키 백업

> [!CAUTION]
> `~/.config/sops/age/keys.txt`를 분실하면 모든 암호화된 Secret을 복호화할 수 없다.
> 안전한 곳에 백업해둘 것. (예: 1Password, 물리 USB 등)

### 새로운 Secret 추가 시

```bash
# 1. 평문 YAML 작성
cat > k8s/apps/new-app/secret.yaml << 'EOF'
apiVersion: v1
kind: Secret
metadata:
  name: new-app-secret
  namespace: prodesk
type: Opaque
stringData:
  API_KEY: "actual-value-here"
EOF

# 2. SOPS 암호화
sops --encrypt k8s/apps/new-app/secret.yaml > k8s/apps/new-app/secret.enc.yaml

# 3. 평문 삭제
rm k8s/apps/new-app/secret.yaml

# 4. kustomization.yaml에 추가
# resources:
#   - secret.enc.yaml
```
