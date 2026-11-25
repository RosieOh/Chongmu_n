# 똑똑한 총무 — 남은 작업 목록

> 기준: v1.3.0 (PR #4·v1.3.0 PR 머지 대기) · 작성일 2026-11-25

## 1. 바로 처리할 것

### 1-1. 실기기 동작 확인
v1.2.0·v1.3.0 기능 중 테스트 코드로 확인할 수 없는 부분입니다.

- [ ] 알림 권한 요청 팝업이 뜨는지 (iOS / Android)
- [ ] 미입금 알림이 예약한 시각(저녁 8시)에 오는지
- [ ] 모두 입금 처리하면 예약 알림이 취소되는지
- [ ] 토스(`toss.me/아이디`) 링크가 토스 앱 송금 화면으로 열리는지
- [ ] 카카오페이(`qr.kakaopay.com`) 링크가 카카오페이로 열리는지
- [ ] (v1.3.0) 금액 계산기 키패드가 작은 화면(iPhone SE)에서 잘 보이는지
- [ ] (v1.3.0) 미수금 장부에서 입금 확인한 내용이 지난 정산·영수증에 반영되는지

### 1-2. PR #4 머지
```
gh pr merge 4 --merge --delete-branch
```

v1.3.0 PR도 이어서 머지합니다 (PR #4 위에 쌓은 브랜치).

### 1-3. 머지 후 정리
- [ ] 로컬 main 동기화, 지난 브랜치 정리
- [ ] 이슈 #3이 닫혔는지 확인
- [ ] 마일스톤 `v1.2.0 정산 편의 기능`, `v1.3.0` 마일스톤 닫기

---

## 2. 다음 기능 (원래 계획)

### 2-1. 광고 연동 (2단계)
`pubspec.yaml`에 `google_mobile_ads`가 주석 처리되어 있습니다.

- [ ] AdMob 앱 ID와 광고 단위 ID 발급
- [ ] iOS `Info.plist`: `GADApplicationIdentifier`, `SKAdNetworkItems` 추가
- [ ] Android `AndroidManifest.xml`: AdMob 앱 ID meta-data 추가
- [ ] 광고 추적 동의(ATT) 팝업 (iOS)
- [ ] PRO 사용자에게는 광고 숨기기
- [ ] 개발 중에는 테스트 광고 ID 사용

### 2-2. 인앱결제 (3단계)
`pubspec.yaml`에 `purchases_flutter`(RevenueCat)가 주석 처리되어 있습니다.

- [ ] App Store Connect / Play Console에 PRO 상품 등록
- [ ] RevenueCat 프로젝트 생성 및 연동
- [ ] 지금은 기기 로컬 값으로만 판단하는 PRO 여부를 실제 결제 상태로 교체
- [ ] 구매 복원 버튼 (iOS 심사 필수)

### 2-3. 보류한 기능 아이디어
- 메뉴별 나눠 내기 (항목마다 참여자 지정)
- 회비 통장 차감 (회비 잔액에서 먼저 빼고 N빵)
- 부분 입금 기록 (2만 원 중 1만 원 입금)
- 공유 메시지 문구 편집
- 영수증 사진 금액 인식·외화 정산·홈 위젯 (패키지가 무겁거나 범위가 커서 보류)

---

## 3. 출시 준비

### 3-1. 빌드 확인
- [ ] **Android:** 이 맥에는 Android SDK가 없어 한 번도 빌드해 보지 못함
  - 알림 플러그인은 compileSdk 37을 요구하고 Flutter 기본값은 36이라 충돌할 수 있음
  - core library desugaring 설정(`desugar_jdk_libs` 2.1.4)이 정상 동작하는지
- [ ] **iOS:** Swift Package Manager 구성과 배포 대상 iOS 15에서 빌드되는지

### 3-2. 앱 아이콘
- [ ] `assets/images/app_icon.png` (1024×1024, 투명 배경 없이) 추가
- [ ] `dart run flutter_launcher_icons` 실행

### 3-3. 스토어 등록 자료
- [ ] 번들 ID / 패키지명 확정
- [ ] Android 서명 키(keystore) 생성 및 보관
- [ ] 스크린샷 (iPhone 6.7"/6.5", Android 휴대전화)
- [ ] 앱 이름, 짧은 설명, 상세 설명
- [ ] 개인정보처리방침 URL (광고를 붙이면 필수)
- [ ] 스토어에 올릴 때마다 `pubspec.yaml`의 빌드 번호(`+N`) 올리기

---

## 참고: 송금 링크 방식
토스·카카오페이 앱을 직접 열면서 금액까지 미리 채우는 주소 형식은 공식 문서가 없어서 쓰지 않았습니다.
대신 사용자가 직접 등록한 송금 링크(`toss.me/아이디`, `qr.kakaopay.com/...`)를 카톡 메시지에 붙이는 방식입니다.
