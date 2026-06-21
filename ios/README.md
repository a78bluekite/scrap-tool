# 스크랩 도구 (iOS)

데스크톱 `scrap_tool.py`의 모바일 버전. iOS는 다른 앱 위에 자동으로 버튼을 띄울 수
없으므로, 텍스트/이미지를 선택한 뒤 **공유 → 스크랩 도구** 를 누르는 방식으로 동작합니다.

- `ScrapApp/` — 메인 앱 (스크랩 목록, 폴더, Claude 질문, 설정)
- `ShareExtension/` — 공유 시트 확장. 다른 앱에서 텍스트/URL/이미지를 공유받아 저장
- `Shared/` — 두 타깃이 공유하는 모델/저장소/OCR 코드
- App Group(`group.com.scraptool.app`)으로 두 타깃이 같은 데이터를 공유

## 빌드 (Mac 없이, GitHub Actions 사용)

1. 이 저장소를 GitHub에 push
2. GitHub 저장소 → **Actions** 탭 → "Build unsigned IPA" 워크플로 → **Run workflow**
   (또는 `ios/` 변경 후 main에 push하면 자동 실행)
3. 빌드가 끝나면 **Artifacts**에서 `ScrapApp-ipa.zip` 다운로드 → 압축 풀면 `ScrapApp.ipa`

빌드는 서명 없이(`CODE_SIGNING_ALLOWED=NO`) 진행됩니다. 실제 서명은 설치 시
Sideloadly가 사용자의 Apple ID로 직접 처리합니다.

## 아이폰에 설치 (Windows + Sideloadly, 무료 Apple ID)

1. Windows에 [Sideloadly](https://sideloadly.io) 설치, 아이폰을 USB로 연결
2. Sideloadly에 `ScrapApp.ipa` 드래그 → Apple ID 입력 → Start
3. 아이폰에서: **설정 → 일반 → VPN 및 기기 관리** → 개발자 앱 신뢰
4. 공유 시트에 "스크랩 도구"가 안 보이면: 공유 시트 맨 끝 **"더 보기"** → 스위치 켜기
   (필요하면 위로 끌어서 자주 쓰는 줄로 이동)

### 주의: 7일 재서명

무료 Apple ID로 사이드로딩한 앱은 **7일마다 재설치**해야 합니다 (Apple 정책).
Sideloadly를 다시 켜서 같은 `.ipa`로 재설치하면 데이터는 유지됩니다(App Group
저장소는 앱 삭제 전까지 보존). 매년 $99 Apple Developer Program에 가입하면
유효기간이 1년으로 늘어납니다.

## 처음 실행 시

1. 앱 실행 → 우측 상단 ⚙ 설정 → Anthropic API 키 입력 (console.anthropic.com에서 발급)
2. 다른 앱(사파리, 카카오톡 등)에서 텍스트 선택 → 공유 → 스크랩 도구 → 폴더 선택 후
   "✂ 스크랩" 누르면 저장
3. 메인 앱에서 항목을 탭하면 Claude에게 질문하거나 클립보드로 복사 가능
