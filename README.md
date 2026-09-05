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
  - 기본 설정([include/config.h](include/config.h))

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

프로젝트 소스는 역할과 언어 특성에 따라 **헤더 파일(`include/`)**, **순수 C++ 구현체(`src/cpp/`)**, **Objective-C++ 구현체(`src/mm/`)**로 명확히 구분되어 있습니다.

```
app-browser/
├── CMakeLists.txt              # 프로젝트 메인 CMake 빌드 설정 (타겟 분리, 라이선스 번들링 포함)
├── LICENSE                     # 본 프로젝트 라이선스(MIT) 및 서드파티(CEF/Chromium) 라이선스 전문
├── README.md                   # 문서
├── scripts/
│   └── setup_cef.sh            # CEF 바이너리 자동 다운로드/추출 스크립트
├── resources/
│   └── mac/
│       ├── Info.plist.in       # 메인 앱 번들 메타데이터 템플릿
│       └── helper-Info.plist.in # CEF Helper 프로세스 번들 메타데이터 템플릿
├── include/                    # [헤더 파일] 공용 선언 및 데이터 구조 (.h)
│   ├── app.h                   # CefApp 및 CefBrowserProcessHandler 인터페이스 선언
│   ├── client.h                # CefClient 및 생명주기/디스플레이/메뉴 핸들러 선언
│   └── config.h                # 시작 URL, 창 크기 등 설정 파서 인라인 헤더
├── src/
│   ├── cpp/                    # [C++ 구현 파일] 순수 C++ 로직 (.cpp)
│   │   ├── app.cpp             # CEF Views 기반 브라우저 뷰 및 탑레벨 윈도우 생성 로직
│   │   ├── client.cpp          # 타이틀 동기화, 팝업 제어, 컨텍스트 메뉴 동작 구현
│   │   └── helper_mac.cpp      # CEF 보조 프로세스(렌더러, GPU, 플러그인 등) 진입점
│   └── mm/                     # [Objective-C++ 구현 파일] macOS 네이티브 연동 (.mm)
│       └── main_mac.mm         # Cocoa NSApplication, NSMenu, 앱 수명주기 및 CEF 메인 진입점
└── third_party/
    └── cef/                    # CEF 프레임워크 및 바이너리 배포본 (자동 설치됨)
```

### 구성 분리 원칙
- **`include/` (헤더 파일)**: 클래스 선언, 인터페이스, 설정 구조체를 정의하며 컴파일러 Include Path로 자동 참조됩니다.
- **`src/cpp/` (C++ 파일)**: 플랫폼 비종속적이거나 CEF C++ Views API를 사용하는 순수 C++ 코드로, 표준 C++20 옵션으로 컴파일됩니다.
- **`src/mm/` (Objective-C++ 파일)**: macOS Cocoa(`NSApplication`, `NSMenu`, `NSApplicationDelegate`) 런타임과 직접 통신하는 구현체로, ARC(Automatic Reference Counting) 및 Objective-C++ 런타임을 통해 컴파일됩니다.

---

## 라이선스 및 서드파티 고지사항 (License & Acknowledgements)

### 1. App Browser 라이선스
App Browser 프로젝트 소스 코드는 [MIT License](LICENSE) 하에 배포됩니다.

### 2. Chromium Embedded Framework (CEF) 라이선스 준수
본 프로젝트는 **Chromium Embedded Framework (CEF)** 바이너리 및 라이브러리를 포함/사용하며, CEF의 **BSD 3-Clause License** 조건을 준수합니다.

- **조건 1 (소스 코드 재배포)**: 본 저장소의 소스 코드 배포물([LICENSE](LICENSE) 파일 및 관련 문서)에 Marshall A. Greenblatt 및 Google Inc.의 저작권 고지, 사용 조건, 면책 조항 원문을 유지합니다.
- **조건 2 (바이너리 형태 재배포)**: 빌드된 `AppBrowser.app` 번들 내부 `Contents/Resources/` 경로에 `CEF_LICENSE.txt` 및 `CEF_CREDITS.html`이 자동으로 복사·동봉되어 배포 시 라이선스 및 저작권 정보가 항상 제공됩니다.
- **조건 3 (이름 사용 제한)**: Google Inc. 또는 Chromium Embedded Framework의 사전 서면 승인 없이 해당 명칭을 제품 홍보나 보증 용도로 사용하지 않습니다.

### 3. Chromium 및 오픈소스 소프트웨어 크레딧
CEF 및 Chromium에는 다양한 오픈소스 컴포넌트가 포함되어 있습니다:
- 전체 서드파티 소프트웨어 라이선스 목록은 앱 번들 내 `Contents/Resources/CEF_CREDITS.html` 또는 본 저장소의 [third_party/cef/CREDITS.html](third_party/cef/CREDITS.html)에서 확인하실 수 있습니다.
- 브라우저 실행 중 `about:credits` 또는 `chrome://credits`에 접속하여 확인할 수도 있습니다.