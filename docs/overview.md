# AppBrowser 프로젝트 개요 및 구조 가이드

## 1. 프로젝트 소개 (Introduction)

**AppBrowser**는 Chromium Embedded Framework (CEF)와 macOS Cocoa (AppKit)를 결합하여 제작된 **독립형 웹 애플리케이션 브라우저 및 프로세스 관리자**입니다.

일반적인 브라우저가 하나의 창 안에서 탭(Tab)으로 사이트를 관리하는 것과 달리, AppBrowser는 각 웹 사이트나 검색 결과를 **완전히 독립된 개별 macOS GUI 프로세스**로 실행합니다. 또한 시스템 관리자 창을 통해 실행 중인 모든 프로세스를 폴더 기반으로 그룹화하고, 사용자 지정 이름으로 식별하며, 전용 Dock 아이콘을 부여하여 마치 네이티브 데스크톱 앱처럼 활용할 수 있도록 설계되었습니다.

---

## 2. 핵심 기능 요약 (Key Features)

1. **독립 프로세스 분리 모델 (Multi-Process Isolation)**:
   - 검색창이나 즐겨찾기에서 실행된 각 웹 페이지는 독립된 자식 프로세스(`--child`)로 구동됩니다.
   - 단일 탭의 충돌이나 메모리 누수가 전체 애플리케이션에 영향을 주지 않으며, 각 프로세스는 독립적인 캐시 및 쿠키 저장소를 가집니다.
2. **미니멀 플로팅 검색창 (Floating Search Bar)**:
   - 네이티브 툴바를 없앤 프레임리스(`IsFrameless`) 반투명 플로팅 디자인.
   - Google 실시간 검색어 자동 완성, 키보드 탐색, URL 직접 입력 지원.
   - 검색 실행 시 부모 프로세스로 IPC 통지를 전달하고 자식 브라우저를 생성.
3. **폴더형 프로세스 관리자 (Process Manager Dashboard)**:
   - 실행 중인 모든 자식 프로세스의 실시간 감시, 포커스 활성화(`Focus`), 개별/전체 종료(`Terminate`).
   - 프로세스 ID(PID) 대신 사용자가 읽기 쉬운 친절한 프로세스명 제공 및 더블 클릭 인라인 이름 변경.
   - 가상 폴더(Group) 생성, 이름 변경, 삭제 및 드롭다운을 통한 프로세스의 그룹 간 자유로운 이동.
   - 불투명한 고대비 솔리드 액션 툴바(50% 불투명도 및 고대비 버튼).
4. **미니멀 즐겨찾기 창 (Bookmarks Window)**:
   - 네이티브 툴바 없는 프레임리스 글래스모피즘 디자인.
   - 화면 하단 중앙(Dock 바로 위)에 최적화 배치.
   - 아이콘 그리드를 통한 프리셋 주소 즉시 실행.
   - 추가, 수정, 삭제 및 `localStorage` 영속화 지원.
5. **웹 앱 전용 macOS Dock 아이콘 동적 적용**:
   - 자식 웹 앱이 실행되면 Google 128px 고화질 파비콘 서비스 및 CEF 렌더러의 `<link rel="apple-touch-icon">`을 통해 실시간으로 파비콘을 다운로드.
   - macOS 표준 스퀴클(Squircle) 256x256 캔버스에 렌더링하여 해당 프로세스의 macOS Dock 아이콘을 웹 앱 고유 아이콘으로 즉시 교체.
   - 프로세스 관리자 목록에서도 각 프로세스 카드에 해당 사이트의 실제 파비콘 표시.
6. **안전한 전체 종료 (Clean Shutdown)**:
   - 프로세스 관리자 창 닫기 시 모든 자식 프로세스, 부속 창(검색창, 즐겨찾기창), CEF 헬퍼 프로세스까지 일괄 정상 정리.

---

## 3. 디렉터리 및 파일 구조 트리 (Directory Structure)

```text
app-browser/
├── CMakeLists.txt                 # CMake 메인 빌드 설정 파일 (macOS 번들, CEF 라이브러리 링크)
├── README.md                      # 프로젝트 영문 소개 및 빌드 기본 문서
├── LICENSE                        # 라이선스 문서
├── docs/                          # 프로젝트 상세 기술 문서
│   ├── overview.md                # [본 문서] 프로젝트 개요, 아키텍처 및 폴더 구조
│   ├── architecture.md            # 멀티프로세스 모델, IPC, 생명주기 기술 상세
│   └── source_code_reference.md   # C++, Obj-C++, 웹 프론트엔드 전 소스 코드 상세 설명
├── include/                       # C++ / Objective-C++ 공통 헤더
│   ├── app.h                      # CEF 애플리케이션 진입점 및 macOS 윈도우 헬퍼 함수 선언
│   ├── client.h                   # CEF 핸들러(Display, LifeSpan, Request, ContextMenu) 선언
│   ├── config.h                   # CLI 인수 파싱 및 창 설정 구조체(WindowConfig) 정의
│   └── process_manager.h          # 자식 프로세스 관리자(싱글톤) 및 IPC 통신 선언
├── src/                           # 애플리케이션 구현 소스 코드
│   ├── cpp/                       # C++ 핵심 로직
│   │   ├── app.cpp                # 윈도우 대리자(WindowDelegate), 창 생성 및 종료 생명주기
│   │   ├── client.cpp             # 브라우저 이벤트 콜백, action:// 프로토콜, 파비콘 다운로드
│   │   └── helper_mac.cpp         # macOS 보조 서브프로세스(Helper) 엔트리포인트
│   └── mm/                        # Objective-C++ (macOS Cocoa / AppKit 연동)
│       ├── main_mac.mm            # 메인 엔트리포인트, NSApplication 위임자, Dock 아이콘 생성
│       └── process_manager.mm     # NSTask 기반 프로세스 생성/추적, NSDistributedNotificationCenter IPC
├── resources/                     # 정적 리소스 및 프론트엔드 웹 UI
│   ├── mac/                       # macOS 앱 번들 메타데이터
│   │   ├── Info.plist.in          # 메인 앱 번들 Info.plist 템플릿
│   │   └── helper-Info.plist.in   # 헬퍼 앱 번들 Info.plist 템플릿
│   └── web/                       # CEF 브라우저 뷰에 로드되는 웹 UI
│       ├── search/                # 검색창 UI (프레임리스, 자동완성)
│       │   ├── index.html
│       │   ├── style.css
│       │   └── search.js
│       ├── manager/               # 프로세스 관리자 대시보드 UI (폴더, 그룹, 이름변경)
│       │   ├── index.html
│       │   ├── style.css
│       │   └── manager.js
│       └── bookmarks/             # 즐겨찾기 창 UI (아이콘 그리드, CRUD 모달)
│           ├── index.html
│           ├── style.css
│           └── bookmarks.js
├── scripts/                       # 빌드 보조 스크립트
│   └── setup_cef.sh               # CEF 바이너리 자동 다운로드 및 압축 해제 스크립트
└── third_party/                   # 외부 서드파티 라이브러리
    └── cef/                       # Chromium Embedded Framework 바이너리 배포판 (git 제외)
```

---

## 4. 빌드 및 실행 방법 (Build & Run Guide)

### 1) 사전 요구 사항 (Prerequisites)
- **운영체제**: macOS 12.0 Monterey 이상 (Apple Silicon arm64 및 Intel x86_64 지원)
- **개발 도구**: Xcode Command Line Tools (`xcode-select --install`)
- **빌드 시스템**: CMake 3.21 이상 (`brew install cmake`)
- **CEF 바이너리 배포판**: `scripts/setup_cef.sh`를 통해 자동 설치

### 2) 빌드 단계
```bash
# 1. 저장소 클론 및 디렉터리 이동
cd app-browser

# 2. CEF 바이너리 다운로드 및 압축 해제 (최초 1회)
./scripts/setup_cef.sh

# 3. CMake 빌드 디렉터리 구성 (Release 모드)
cmake -B build -DCMAKE_BUILD_TYPE=Release

# 4. 컴파일 및 번들 생성
cmake --build build
```

### 3) 실행 단계
```bash
# 생성된 macOS 앱 번들 실행
open build/Release/AppBrowser.app

# 또는 특정 URL을 직접 지정하여 독립 프로세스로 실행
build/Release/AppBrowser.app/Contents/MacOS/AppBrowser --child --url="https://github.com"
```
