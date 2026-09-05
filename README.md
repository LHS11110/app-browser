# App Browser

Chromium Embedded Framework (CEF) 기반의 **C++ 미니멀 앱 브라우저 (Site-Specific Browser / SSB)**입니다.

기존 웹 브라우저의 번잡한 주소 표시줄, 탭 바, 북마크 바, 내비게이션 버튼 등 불필요한 UI 요소를 모두 제거하고, 웹 앱을 전용 데스크톱 네이티브 앱처럼 실행할 수 있도록 제작되었습니다.

---

## 주요 특징

- **미니멀 데스크톱 앱 인터페이스**:
  - 주소창, 툴바, 불필요한 브라우저 UI 없이 전체 화면을 웹 앱 뷰로 꽉 채움
  - 창 이동 및 크기 조절이 용이한 macOS 네이티브 윈도우 지원
- **웹 앱 최적화 동작**:
  - 웹 페이지의 `<title>` 변경 시 네이티브 창 타이틀 자동 동기화 (`CefDisplayHandler`)
  - 새 창(팝업 / `target="_blank"`) 클릭 시 현재 창 내부 탐색으로 유지하여 데스크톱 앱 경험 보장 (`CefLifeSpanHandler`)
  - 웹 페이지 소스 보기, 검사 등 불필요한 브라우저 메뉴를 정리하고 필수 편집 기능(복사/붙여넣기/잘라내기/전체선택)만 제공 (`CefContextMenuHandler`)
  - macOS 표준 단축키(`Cmd+C`, `Cmd+V`, `Cmd+X`, `Cmd+A`, `Cmd+Q`) 기본 지원
- **유연한 타겟 URL 설정**:
  - 커맨드라인 인자(`--url=...`, `--title=...`, `--width=...`, `--height=...`)
  - 환경 변수(`APP_BROWSER_URL=...`)
  - 기본 설정(`src/config.h`)

---

## 시스템 요구사항

- **OS**: macOS 12.0+ (Apple Silicon arm64)
- **도구**: CMake 3.21 이상, Apple Clang (C++20 지원)
- **프레임워크**: Chromium Embedded Framework (CEF) prebuilt 바이너리

---

## 빠른 시작 (Quick Start)

### 1. CEF 의존성 다운로드
제공되는 자동 셋업 스크립트를 통해 Spotify CDN에서 검증된 최신 CEF 바이너리를 다운로드 및 설정합니다.
```bash
./scripts/setup_cef.sh
```

### 2. 프로젝트 빌드
```bash
# CMake 구성 (최초 1회)
cmake -B build -S .

# 빌드 실행
cmake --build build -j$(sysctl -n hw.ncpu)
```

빌드가 완료되면 `build/Release/AppBrowser.app` (또는 `build/AppBrowser.app`)이 생성됩니다.

---

## 실행 방법

### 기본 실행
```bash
open build/Release/AppBrowser.app
```

### 원하는 웹 앱 URL로 직접 실행
터미널에서 실행 바이너리에 직접 인자를 전달하여 원하는 웹 앱을 앱 형태로 바로 띄울 수 있습니다:

```bash
# Notion 실행 예시
./build/Release/AppBrowser.app/Contents/MacOS/AppBrowser --url="https://www.notion.so" --title="Notion"

# YouTube Music 실행 예시
./build/Release/AppBrowser.app/Contents/MacOS/AppBrowser --url="https://music.youtube.com" --title="YouTube Music" --width=1440 --height=900

# 로컬 개발 서버(Next.js, Vite 등) 실행 예시
./build/Release/AppBrowser.app/Contents/MacOS/AppBrowser --url="http://localhost:3000" --title="My Local Web App"
```

### 환경 변수를 통한 실행
```bash
APP_BROWSER_URL="https://linear.app" open build/Release/AppBrowser.app
```

---

## 프로젝트 구조

```
app-browser/
├── CMakeLists.txt              # 프로젝트 메인 CMake 빌드 설정
├── README.md                   # 문서
├── scripts/
│   └── setup_cef.sh            # CEF 바이너리 자동 다운로드/추출 스크립트
├── resources/
│   └── mac/
│       ├── Info.plist.in       # 메인 앱 번들 메타데이터 템플릿
│       └── helper-Info.plist.in # CEF Helper 프로세스 번들 메타데이터 템플릿
├── src/
│   ├── config.h                # 시작 URL, 창 크기 등 설정 파서
│   ├── app.h                   # CefApp 및 CefBrowserProcessHandler 인터페이스
│   ├── app_mac.mm              # Cocoa NSWindow 및 CEF 브라우저 생성
│   ├── client.h                # CefClient 및 생명주기/디스플레이/메뉴 핸들러 인터페이스
│   ├── client.mm               # 타이틀 동기화, 팝업 제어, 컨텍스트 메뉴 구현
│   ├── main_mac.mm             # macOS 진입점, Cocoa 애플리케이션 및 CEF 초기화
│   └── helper_mac.cc           # CEF 보조 프로세스(렌더러, GPU 등) 진입점
└── third_party/
    └── cef/                    # CEF 프레임워크 및 라이브러리 (자동 설치됨)
```