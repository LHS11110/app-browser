# App Browser

Chromium Embedded Framework (CEF) 기반의 **격리형 멀티 프로세스 앱 브라우저 (Multi-Process Site-Specific Browser)**입니다.

부모 프로세스가 **프로세스 관리 센터(대시보드)**와 **검색창**을 총괄 관리하며, 검색창이나 URL 입력 시 각 웹 앱을 **독립된 자식 프로세스(Child Process) 및 독립 창**으로 분리 실행하여 완벽한 격리와 쾌적한 데스크톱 앱 경험을 제공합니다.

---

## 주요 특징

- **부모-자식 멀티 프로세스 격리 아키텍처**:
  - **부모 프로세스 (Process Manager)**: 전체 앱 생명주기 및 실행 중인 자식 프로세스 모니터링/제어 담당
  - **독립 자식 프로세스 (Child Browser)**: 각 웹 사이트/웹 앱이 완전히 독립된 OS 프로세스(`AppBrowser --child --url=...`) 및 창으로 기동되어 충돌이나 메모리 간섭이 원천 차단됨
- **HTML/CSS/JS 기반 프로세스 관리 센터 (대시보드)**:
  - 실행 중인 자식 앱의 실시간 목록(PID, 사이트명, URL, 시작 시각, 상태) 확인
  - 각 자식 프로세스를 앞으로 가져오는 **[↗️ 활성화]** 기능
  - 비정상 동작 또는 불필요한 앱을 즉시 종료하는 **[🛑 개별 종료]** 및 **[전체 종료]** 지원
  - 검색창을 즉시 띄우는 **[🔍 검색창 열기]** 및 대시보드 내 **[⚡️ 빠른 URL 실행]** 제공
- **미니멀 플로팅 검색창**:
  - Spotlight / Raycast 스타일의 컴팩트한 검색창(`640 × 64`)
  - 검색어 또는 URL 입력 후 `Enter` 시 부모 프로세스가 새로운 자식 창을 생성하고, 검색창은 즉시 다음 검색을 위해 초기화됨
- **웹 앱 최적화 네이티브 동작**:
  - 주소창, 툴바 등 불필요한 크롬 요소를 제거하여 웹 앱 본연의 뷰로 화면을 꽉 채움
  - 웹 페이지 `<title>` 변경 시 네이티브 창 타이틀 자동 동기화 (`CefDisplayHandler`)
  - 새 창(팝업 / `target="_blank"`) 클릭 시 현재 창 내부 탐색으로 유지하여 데스크톱 앱 경험 보장 (`CefLifeSpanHandler`)
  - macOS 표준 단축키(`Cmd+C`, `Cmd+V`, `Cmd+X`, `Cmd+A`, `Cmd+Q`) 기본 지원
- **유연한 타겟 URL 설정**:
  - 커맨드라인 인자(`--url=...`, `--title=...`, `--width=...`, `--height=...`, `--child`)
  - 환경 변수(`APP_BROWSER_URL=...`)

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

### 기본 실행 (프로세스 관리 센터 + 검색창 동시 실행)
```bash
open build/Release/AppBrowser.app
```
실행 시 화면에 **프로세스 관리 창(`440 × 740`, 세로형 리스트 및 반투명 글래스 스타일)**과 플로팅 **검색창(`640 × 64`)**이 동시에 표시됩니다.
- 검색창에 `github.com` 또는 `apple` 같은 검색어를 입력하고 `Enter`를 누르면 새로운 독립 자식 창이 열립니다.
- 프로세스 관리 센터에서 방금 뜬 앱의 PID와 상태를 확인하고 포커스하거나 종료할 수 있습니다.

### 특정 웹 앱을 단독 자식 창으로 직접 실행
```bash
# Notion 실행 예시
./build/Release/AppBrowser.app/Contents/MacOS/AppBrowser --child --url="https://www.notion.so" --title="Notion"

# YouTube Music 실행 예시
./build/Release/AppBrowser.app/Contents/MacOS/AppBrowser --child --url="https://music.youtube.com" --title="YouTube Music"
```

---

## 프로젝트 구조

프로젝트 소스는 역할과 언어 특성에 따라 **헤더 파일(`include/`)**, **순수 C++ 구현체(`src/cpp/`)**, **Objective-C++ 구현체(`src/mm/`)**, **웹 대시보드 리소스(`resources/web/`)**로 명확히 구분되어 있습니다.

```
app-browser/
├── CMakeLists.txt              # 프로젝트 메인 CMake 빌드 설정 (타겟 분리, 리소스/라이선스 번들링)
├── LICENSE                     # 본 프로젝트 라이선스(MIT) 및 서드파티(CEF/Chromium) 라이선스 전문
├── README.md                   # 문서
├── scripts/
│   └── setup_cef.sh            # CEF 바이너리 자동 다운로드/추출 스크립트
├── resources/
│   ├── mac/
│   │   ├── Info.plist.in       # 메인 앱 번들 메타데이터 템플릿
│   │   └── helper-Info.plist.in # CEF Helper 프로세스 번들 메타데이터 템플릿
│   └── web/                    # [자체 관리 웹 리소스]
│       ├── search/             # [검색창 웹 리소스 (HTML/CSS/JS 분리)]
│       │   ├── index.html      # 컴팩트 검색창 마크업
│       │   ├── style.css       # 미니멀 플로팅 옴니바 스타일
│       │   └── search.js       # 부모 프로세스에 자식 프로세스 기동 요청 (action://spawn)
│       └── manager/            # [프로세스 관리 창 웹 리소스 (HTML/CSS/JS 분리)]
│           ├── index.html      # 프로세스 리스트 뷰 마크업
│           ├── style.css       # 리스트 형태 다크 테마 대시보드 스타일
│           └── manager.js      # 실시간 프로세스 목록 갱신 및 제어 스크립트
├── include/                    # [헤더 파일] 공용 선언 및 데이터 구조 (.h)
│   ├── app.h                   # CefApp 및 CefBrowserProcessHandler 인터페이스 선언
│   ├── client.h                # CefClient 및 핸들러 인터페이스 선언
│   ├── config.h                # 설정 구조체, 자식 모드 플래그 및 파서
│   └── process_manager.h       # 자식 프로세스 수명주기/모니터링 관리자 선언
├── src/
│   ├── cpp/                    # [C++ 구현 파일] 순수 C++ 로직 (.cpp)
│   │   ├── app.cpp             # 부모(관리창+검색창) 및 자식 브라우저 뷰/창 생성 로직
│   │   ├── client.cpp          # action:// 프로토콜 가로채기 및 타이틀/팝업 제어
│   │   └── helper_mac.cpp      # CEF 보조 프로세스(렌더러, GPU, 플러그인 등) 진입점
│   └── mm/                     # [Objective-C++ 구현 파일] macOS 네이티브 연동 (.mm)
│       ├── main_mac.mm         # Cocoa 앱 수명주기, 캐시 격리, 서브프로세스 경로 설정
│       └── process_manager.mm  # NSTask 기반 자식 프로세스 생성/종료 및 NSRunningApplication 활성화
└── third_party/
    └── cef/                    # CEF 프레임워크 및 바이너리 배포본 (자동 설치됨)
```

### 구성 분리 원칙
- **`resources/web/` (자체 웹 리소스)**:
  - **`search/` (검색창)**: 검색창 마크업, 스타일, 스크립트(`index.html`, `style.css`, `search.js`)가 전용 디렉토리로 완전 격리되어 관리됩니다.
  - **`manager/` (프로세스 관리 창)**: 자식 프로세스를 리스트 형태로 관리하는 전용 대시보드(`index.html`, `style.css`, `manager.js`)로 완전 분리되어 독립적으로 확장 가능합니다.
  - 외부 번들러나 웹팩 없이 브라우저 표준 기술(Vanilla HTML/CSS/JS)로 작성되어 가볍고 빠르며, 빌드 시 앱 번들의 `Contents/Resources/web/`로 자동 패키징됩니다.
- **`include/` (헤더 파일)**: 클래스 선언, 인터페이스, 설정 구조체를 정의하며 컴파일러 Include Path로 자동 참조됩니다.
- **`src/cpp/` (C++ 파일)**: 플랫폼 비종속적이거나 CEF C++ Views API를 사용하는 순수 C++ 코드로, 표준 C++20 옵션으로 컴파일됩니다.
- **`src/mm/` (Objective-C++ 파일)**: macOS Cocoa(`NSApplication`, `NSTask`, `NSRunningApplication`) 런타임과 직접 통신하는 구현체로, ARC(Automatic Reference Counting) 및 Objective-C++ 런타임을 통해 컴파일됩니다.

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