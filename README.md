# 똑똑한 총무 - 1/N이 안 맞는 회식 정산 계산기 (chongmu_n)

## 0. 처음 한 번만: 개발 도구 설치 (Android Studio 없이)

```bash
# Homebrew 가 없다면 먼저 https://brew.sh 의 설치 명령 실행
brew install --cask flutter
brew install cocoapods

# App Store 에서 Xcode 설치 후
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -runFirstLaunch
xcodebuild -downloadPlatform iOS

flutter doctor   # Android 관련 ✗ 표시는 무시해도 됩니다
```

## 1. 프로젝트 완성 + 실행

```bash
cd ~/Desktop/DevRosieOh/chongmu/chongmu_n

# 이미 있는 lib/, pubspec.yaml 은 그대로 두고 ios/android 폴더만 생성됩니다
flutter create . --project-name chongmu_n --org com.chongmu --platforms ios,android

# 홈 화면 앱 이름 + 사진 저장 권한 문구 (iOS)
plutil -replace CFBundleDisplayName -string "똑똑한 총무" ios/Runner/Info.plist
plutil -replace NSPhotoLibraryAddUsageDescription -string "정산 영수증 이미지를 사진첩에 저장하기 위해 사용합니다." ios/Runner/Info.plist

# 홈 화면 앱 이름 (Android)
sed -i '' 's/android:label="chongmu_n"/android:label="똑똑한 총무"/' android/app/src/main/AndroidManifest.xml

flutter pub get
open -a Simulator
flutter run
```

## 2. 로고 / 앱 아이콘

| 파일 | 경로 | 권장 |
|---|---|---|
| 헤더·워터마크 로고 | `assets/images/logo.png` | 512×512 정사각형 PNG |
| 앱 아이콘 | `assets/images/app_icon.png` | 1024×1024, 투명 배경 없음 |

로고를 넣은 뒤 시뮬레이터 터미널에서 `R`(대문자, 핫 리스타트)을 누르세요.

앱 아이콘을 넣은 뒤:

```bash
dart run flutter_launcher_icons
flutter run
```

## 3. 출시 전 필수 체크
- [ ] RevenueCat 결제 연동 (`ProManager.purchase / restore` 의 TODO) — 연동 전 출시하면 애플 심사 반려
- [ ] AdMob 연동 (`BannerAdPlaceholder`, `_saveImage` 의 TODO)
- [ ] 개인정보처리방침 URL 준비 (App Store Connect 입력 필수)
