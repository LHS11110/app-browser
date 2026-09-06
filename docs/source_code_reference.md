# AppBrowser 소스 코드 상세 설명서 (Source Code Reference)

본 문서는 프로젝트에 포함된 모든 C++, Objective-C++, 웹 프론트엔드 리소스 및 빌드 설정 파일의 역할과 내부 구현 코드를 함수 단위로 상세히 설명합니다.

---

## 1. C++ / Objective-C++ 헤더 및 소스 코드

### 1) [`include/config.h`](../include/config.h)
애플리케이션의 CLI 명령행 인수 및 윈도우 초기 설정값을 관리하는 헤더입니다.

- **`struct WindowConfig`**:
  - `title`: 창 타이틀 문자열.
  - `url`: 브라우저가 최초로 로드할 웹 URL.
  - `manager_url`: 프로세스 관리자 HTML 경로 (`web/manager/index.html`).
  - `search_url`: 검색창 HTML 경로 (`web/search/index.html`).
  - `bookmarks_url`: 즐겨찾기 HTML 경로 (`web/bookmarks/index.html`).
  - `width`, `height`, `min_width`, `min_height`: 윈도우 크기 및 최소 제약 크기.
  - `is_child`: 자식 브라우저 프로세스 모드 여부 (`--child`).
  - `is_search`: 독립 검색창 자식 프로세스 모드 여부 (`--search`).
  - `parent_pid`: 부모 프로세스 PID (`--parent-pid=<PID>`, IPC 알림 전송용).
  - `is_translucent`, `alpha`: 반투명 윈도우 적용 여부 및 투명도 수치 (0.0 ~ 1.0).
- **`ParseConfig(int argc, char* argv[])`**:
  - 환경 변수(`APP_BROWSER_URL`) 및 CLI 플래그(`--child`, `--search`, `--url=...`, `--width=...` 등)를 순회하며 `WindowConfig` 구조체 인스턴스를 조립하여 반환합니다.

---

### 2) [`include/app.h`](../include/app.h) & [`src/cpp/app.cpp`](../src/cpp/app.cpp)
CEF 브라우저 프로세스 핸들러 및 윈도우 생성/대리자(Delegate), 전역 생명주기를 담당합니다.

#### 주요 전역 함수:
- **`QuitAppCleanly()`**:
  - 전역 종료 플래그(`g_is_quitting`)를 설정하여 모든 `CanClose`가 즉시 승인되도록 전환.
  - `ProcessManager::TerminateAll()` 및 `CloseAllWindows()` 호출.
  - 모든 브라우저를 닫고 `CefQuitMessageLoop()` 호출 후, 400ms 안전 타이머로 `exit(0)` 실행.
- **`PositionWindowAtBottom(handle, width, height, margin)`**:
  - 화면 작업 영역의 하단 중앙(Dock 바로 위)에 윈도우를 정렬하는 macOS 네이티브 배치 함수.
- **`SetAppDockIconForUrl(url)` / `SetAppDockIconFromData(data, size)`**:
  - 웹 앱의 파비콘을 macOS Dock 아이콘으로 합성 및 변경.
- **`SetWindowOpaque(handle)`**:
  - macOS 네이티브 NSWindow를 완전 불투명(opaque=YES, alpha=1.0)으로 설정하는 헬퍼 함수.
- **`ExtractDomainFromUrl(url)`**:
  - 주어진 URL에서 경로(`path`), 쿼리스트링 등을 제외하고 순수 도메인 호스트명(예: `google.com`, `github.com`)만을 추출하여 소문자로 정규화.
- **`HashDomainToNaturalNumber(domain)`**:
  - 도메인 문자열을 64-bit FNV-1a 해시 알고리즘을 통해 결정론적 양의 자연수(`uint64_t`)로 변환 (`Child_<DomainHash>` 캐시 디렉터리 식별자 생성).

#### 내부 클래스:
- **`AppBrowserWindowDelegate` (`CefWindowDelegate`)**:
  - `OnWindowCreated(window)`: 레이아웃 적용, 크기 조정, 배경 투명화(`SetBackgroundColor(0,0,0,0)`), 화면 배치(하단 또는 중앙), 윈도우 활성화.
  - `IsFrameless(window)`: 검색창(`is_search_`) 및 즐겨찾기창(`is_bookmarks_`)에 대해 `true`를 반환하여 네이티브 타이틀바 제거.
  - `CanClose(window)`:
    - `g_is_quitting == true`인 경우 무조건 `true` 반환.
    - 관리자 창인 경우 `QuitAppCleanly()` 트리거 후 `true` 반환.
    - 즐겨찾기 창인 경우 창을 파괴하지 않고 숨기기(`window->Hide()`, `return false`).
  - `OnWindowDestroyed(window)`: 윈도우 파괴 시 관리자나 검색창의 종료를 `ProcessManager`에 통지.
- **`AppBrowserApp::OnContextInitialized()`**:
  - CEF UI 스레드가 초기화된 직후 실행되는 핵심 진입점.
  - `config_.is_child`인 경우: 독립 웹 브라우저 윈도우 생성.
  - `config_.is_search`인 경우: 독립 검색창 윈도우 생성.
  - 부모 프로세스인 경우:
    1. IPC 수신자 초기화 (`InitIpc()`).
    2. 프로세스 관리자 창 생성 (440x740, alpha: 0.70).
    3. 메인 검색창 생성 (640x64, 프레임리스, alpha: 0.70).
    4. 즐겨찾기 창 생성 (540x420, 프레임리스, alpha: 0.90, 하단 배치).
    5. 1초 주기 자식 프로세스 생존 상태 체크 타이머 스케줄링.

---

### 3) [`include/client.h`](../include/client.h) & [`src/cpp/client.cpp`](../src/cpp/client.cpp)
CEF 브라우저 인스턴스들의 이벤트 핸들러(Client)입니다.

- **`OnBeforeBrowse(...)`**:
  - `action://` 접두사를 가진 내부 프로토콜을 가로채어 C++ 기능을 실행:
    - `action://spawn?url=...`: 자식 브라우저 실행.
    - `action://kill?pid=...`: 해당 프로세스 종료.
    - `action://focus?pid=...`: 해당 프로세스 창 활성화.
    - `action://kill-all`: 모든 창 종료 및 세션 파일 초기화.
    - `action://open-search`: 검색창 열기.
    - `action://open-bookmarks` / `action://close-bookmarks`: 즐겨찾기 창 열기/숨기기.
    - `action://update-meta?pid=...&name=...&groupId=...`: 프로세스 이름/그룹 메타데이터 동기화.
    - `action://ready`: 프로세스 관리자 준비 완료 시 최신 프로세스 목록 전송.
- **`OnFaviconURLChange(browser, icon_urls)`**:
  - 웹 페이지가 전달한 파비콘 URL 목록 중 최적의 고화질 아이콘(apple-touch-icon 등)을 선별하여 `CefBrowserHost::DownloadImage`를 호출.
- **`FaviconDownloadCallback` (`CefDownloadImageCallback`)**:
  - 이미지 다운로드 완료 시 `CefWindow::SetWindowAppIcon` 설정 및 `SetAppDockIconFromData`를 통해 macOS Dock 아이콘 갱신.
- **`OnAddressChange(browser, frame, url)`**:
  - 자식 브라우저에서 새 도메인으로 내비게이션 시 Dock 아이콘 자동 동기화.
- **`OnTitleChange(browser, title)`**:
  - 웹 페이지의 `<title>` 변경을 감지하여 윈도우 타이틀 동기화.
- **`OnBeforeContextMenu(...)`**:
  - 불필요한 브라우저 기본 우클릭 메뉴(소스 보기, 뒤로 가기 등)를 제거하고 복사/붙여넣기 등 필수 편집 메뉴만 유지.

---

### 4) [`include/process_manager.h`](../include/process_manager.h) & [`src/mm/process_manager.mm`](../src/mm/process_manager.mm)
부모 프로세스에서 자식 브라우저 프로세스들을 총괄 관리하는 **싱글톤 클래스**입니다.

- **`SpawnChild(url)`**:
  - `[[NSBundle mainBundle] executableURL]`을 사용하여 `NSTask`로 현재 앱의 바이너리를 `--child --url=<URL>` 인자와 함께 실행.
  - 생성된 `pid`, `url`, `start_time`을 `processes_` 벡터에 추가하고 `g_activeTasks`에 보관.
  - 400ms 후 `NSRunningApplication activateWithOptions:`를 통해 새로 뜬 창을 전면 활성화.
- **`TerminateChild(pid)` / `TerminateAll()`**:
  - 해당 PID 또는 등록된 모든 자식 프로세스에 `kill(pid, SIGTERM)` 및 `[task terminate]` 전달.
- **`FocusChild(pid)`**:
  - `NSRunningApplication runningApplicationWithProcessIdentifier:`를 조회하여 창을 최상단으로 포커스.
- **`RefreshProcesses()`**:
  - 1초 주기로 실행되며, `kill(pid, 0)` 신호로 OS 레벨에서 종료된 프로세스를 감지하여 목록에서 자동 제거 후 UI 갱신.
- **`NotifyManagerUI()`**:
  - `processes_` 벡터를 JSON 문자열로 직렬화(`ToJson()`)하여 관리자 웹 뷰의 `window.updateProcessList(json)` JavaScript 함수를 실행.
- **`ShowSearchWindow()` / `ShowBookmarksWindow()`**:
  - 숨겨진 검색창 또는 즐겨찾기창을 보이게 하고 전면 활성화.
  - 즐겨찾기 창의 경우 `PositionWindowAtBottom`을 호출하여 화면 하단에 안정적으로 배치.
- **`SaveSession()`**:
  - 현재 열려 있는 모든 웹 앱(`url`, `name`, `groupId`, `visible`)을 `~/Library/Application Support/AppBrowser/session_apps.json`에 실시간 파일로 기록. 창의 숨김/보임 가시성 상태까지 영구 보존.
- **`RestoreSession()`**:
  - 앱 시작 시 `session_apps.json`을 읽어 이전 세션에서 열려 있던 웹 앱들을 자동 복원 및 스폰. `visible == false`인 앱은 `--hidden` 플래그로 초기부터 백그라운드 숨김 상태로 띄워 폴더 상태와 완벽 일치시킴.
- **`ClearSavedSession()`**:
  - 사용자가 '모든 창 종료'를 실행했을 때 저장된 세션 파일을 삭제하여 다음 시작 시 깨끗한 상태로 기동.
- **`UpdateProcessMeta(pid, name, groupId)`**:
  - 프로세스의 커스텀 이름 및 소속 그룹 변경을 메모리 및 세션 파일에 동기화.
- **`UpdateProcessUrl(pid, url, title)`**:
  - 자식 프로세스에서 전달받은 실시간 전체 URL(경로 및 파라미터 포함) 및 페이지 타이틀을 `processes_`에 갱신하고, `SaveSession()` 및 `NotifyManagerUI()` 호출.
- **`SetChildVisibility(pid, visible)` / `SetGroupVisibility(groupId, visible)`**:
  - 특정 자식 프로세스 또는 지정 폴더(그룹) 내 모든 창에 대해 가시성 플래그를 갱신하고 `SaveSession()` 호출. `NSRunningApplication hide/unhide` 및 `SendVisibilityNotificationToChild`를 통해 창을 숨기거나 복원.
- **`HideCurrentAppProcess(window)`**:
  - 자식 프로세스가 `--hidden`으로 시작될 때 즉시 CEF `window->Hide()`, 네이티브 NSWindow `[[view window] orderOut:nil]`, `[NSApp hide:nil]`을 단 1회 실행하여 화면 깜빡임이나 팝업 없이 백그라운드 숨김 모드로 진입.
- **`InitIpc()` & `SendSpawnNotificationToParent()` / `SendUrlUpdateToParent()` / `SendVisibilityNotificationToChild()`**:
  - `NSDistributedNotificationCenter`를 통해 프로세스 생성 요청(`AppBrowser_Spawn_<pid>`), 자식 브라우저의 실시간 URL/타이틀 변경 알림(`AppBrowser_UrlChange_<pid>`), 창 가시성 제어 알림(`AppBrowser_Visibility_<pid>`)을 부모-자식 간에 통신.
- **`RegisterChildVisibilityIpc(window)`**:
  - 자식 프로세스에서 자신의 가시성 알림(`AppBrowser_Visibility_<pid>`)을 구독하여 CEF `window->Hide()/Show()` 및 `[NSApp hide/unhide]`를 동기화.

---

### 5) [`src/mm/main_mac.mm`](../src/mm/main_mac.mm)
애플리케이션의 최초 진입점(`main`)이자 macOS Cocoa 프레임워크와의 브리지 역할을 합니다.

- **`AppBrowserApplication` (`NSApplication <CefAppProtocol>`)**:
  - CEF의 이벤트 루프와 macOS AppKit의 `sendEvent:`를 안전하게 중계하는 커스텀 NSApplication 클래스.
- **`AppBrowserAppDelegate` (`NSApplicationDelegate`)**:
  - 시스템 메뉴바(App, Edit, Window) 초기화 및 `tryToTerminateApplication:` 처리.
- **`CreateAppIconFromImage(sourceImage)`**:
  - 256x256 크기의 캔버스에 둥근 스퀴클 배경(다크 그라디언트 + 테두리)을 그리고, 중앙에 파비콘을 안티앨리어싱하여 얹는 네이티브 그래픽 합성 엔진.
- **`SetAppDockIconForUrl(url)`**:
  - `NSURLSession`을 사용해 백그라운드에서 Google 고화질 파비콘 API로 이미지를 다운로드하여 Dock 아이콘으로 지정.
- **`SetWindowTranslucent(handle, alpha)`**:
  - `NSWindow`의 `setOpaque:NO`, `backgroundColor:clearColor`, `alphaValue:alpha`, `layer.opaque = NO`를 설정하여 100% 투명 블러 윈도우 구현.
- **`main(argc, argv)`**:
  - `CefScopedLibraryLoader` 로드.
  - 리소스 번들(`Contents/Resources/web/...`)에서 `search`, `manager`, `bookmarks` HTML 파일 경로 탐색 및 `config` 조립.
  - 자식 프로세스일 경우 시작 즉시 `SetAppDockIconForUrl` 실행.
  - 캐시 디렉터리를 `~/Library/Application Support/AppBrowser/` 하위에 부모/자식별로 분리 설정.
  - `CefInitialize()` -> `CefRunMessageLoop()` -> `CefShutdown()` 실행.

---

### 6) [`src/cpp/helper_mac.cpp`](../src/cpp/helper_mac.cpp)
Chromium의 멀티프로세스 아키텍처에서 렌더러, GPU, 플러그인, 유틸리티 등의 작업을 전담하는 보조 실행 파일(`AppBrowser Helper.app`)의 최소 진입점입니다.
- `CefExecuteProcess(main_args, nullptr, nullptr)`를 실행하여 CEF 서브프로세스로서의 역할을 수행합니다.

---

## 2. 웹 프론트엔드 리소스 (Web Resources)

모든 웹 리소스는 빌드 시 CMake의 `copy_app_resources` 타깃에 의해 `AppBrowser.app/Contents/Resources/web/`으로 자동 복사됩니다.

### 1) 검색창: `resources/web/search/`
- **[`index.html`](../resources/web/search/index.html)**:
  - 컴팩트한 플로팅 검색 바 레이아웃, 검색 돋보기 아이콘, 텍스트 인풋, 자동완성 드롭다운 리스트 컨테이너.
- **[`style.css`](../resources/web/search/style.css)**:
  - 배경을 90% 투명(`rgba(18, 25, 42, 0.10)`) 및 32px 블러 처리.
  - `-webkit-app-region: drag`로 전체 바를 드래그 가능하게 설정하고, 인풋 필드는 `no-drag`로 설정.
- **[`search.js`](../resources/web/search/search.js)**:
  - 입력 시 Google Suggest API(`https://suggestqueries.google.com/complete/search?client=firefox&q=...`)를 호출하여 자동완성 목록 렌더링.
  - 키보드 방향키(위/아래)로 추천 검색어 탐색, `Enter` 입력 시 URL 직접 입력 또는 Google 검색 URL로 변환하여 `action://spawn?url=...` 호출.

---

### 2) 프로세스 관리자: `resources/web/manager/`
- **[`index.html`](../resources/web/manager/index.html)**:
  - 상단 브랜딩 및 실행 통계 헤더.
  - 액션 툴바: **[검색창]**, **[즐겨찾기]**, **[새 그룹]**, **[전체 종료]** 4개 버튼.
  - 가상 폴더 및 프로세스 카드 목록 컨테이너 (`#group-list`).
  - 그룹 생성/이름변경 모달, 프로세스 종료 확인 모달.
- **[`style.css`](../resources/web/manager/style.css)**:
  - 툴바 컨테이너(`.header-toolbar`)를 솔리드 다크 슬레이트(`#1e293b`) 및 불투명 버튼(`#334155`)으로 구성하여 높은 가독성과 명확한 대비를 제공.
  - macOS Finder 스타일의 접이식 폴더(열림/닫힘 SVG 아이콘, 배지).
  - 프로세스 카드 내 실제 파비콘 이미지(`.item-favicon`, 14x14px) 표시 스타일.
- **[`manager.js`](../resources/web/manager/manager.js)**:
  - `localStorage`를 통한 가상 폴더(Group) 및 프로세스 이름(Metadata) 영속화.
  - `window.updateProcessList(data)`: C++ 백엔드로부터 최신 프로세스 목록을 수신하여 렌더링.
  - 도메인 추출(`getDomain`)을 통한 Google 파비콘 서비스 연동으로 각 프로세스 카드에 웹 앱 아이콘 자동 표시.
  - 인라인 더블클릭 프로세스명/그룹명 변경, 그룹 간 드롭다운 이동, 활성화(`action://focus`), 종료(`action://kill`).

---

### 3) 즐겨찾기 창: `resources/web/bookmarks/`
- **[`index.html`](../resources/web/bookmarks/index.html)**:
  - 프레임리스 헤더(타이틀, 추가 버튼, 닫기 버튼).
  - 아이콘 카드 그리드 컨테이너 (`#bookmark-grid`).
  - 즐겨찾기 추가/수정 모달(이름, URL), 삭제 확인 모달.
- **[`style.css`](../resources/web/bookmarks/style.css)**:
  - 다크 글래스모피즘(36px 블러, 둥근 모서리 16px, 부드러운 그림자).
  - 105px 최소 너비의 아이콘 카드 그리드.
  - 도메인/이름 기반 다이내믹 그라디언트 원형 아이콘과 호버 시 나타나는 수정(✏️)/삭제(🗑️) 오버레이 버튼.
- **[`bookmarks.js`](../resources/web/bookmarks/bookmarks.js)**:
  - **요구사항 엄격 준수**: 아이콘 기반 접근, 추가, 수정, 삭제 외 기능 배제.
  - 기본 즐겨찾기(Google, Naver, GitHub, YouTube) 제공 및 `localStorage` CRUD.
  - 아이콘 클릭 시 `action://spawn?url=...`로 독립 자식 프로세스 실행.
  - 닫기 버튼 및 `ESC` 키 입력 시 `action://close-bookmarks`로 창 숨김 처리.

---

## 3. CMake 빌드 시스템 ([`CMakeLists.txt`](../CMakeLists.txt))

- **CEF 모듈 연동**:
  - `third_party/cef/cmake/FindCEF.cmake`를 로드하고 `libcef_dll_wrapper`를 빌드하여 정적 링크.
- **macOS 앱 번들 빌드**:
  - 메인 타깃 `AppBrowser`를 `MACOSX_BUNDLE`로 선언하고 `Info.plist.in` 주입.
  - `COPY_MAC_FRAMEWORK`를 통해 `Chromium Embedded Framework.framework`를 번들 내부 `Contents/Frameworks/`로 복사.
- **보조 프로세스(Helper Apps) 생성**:
  - 메인 헬퍼, GPU, Plugin, Renderer 총 4개의 헬퍼 앱을 `helper-Info.plist.in`을 기반으로 생성.
- **웹 리소스 동기화 타깃 (`copy_app_resources`)**:
  - `resources/web/*` 하위의 모든 HTML, CSS, JS 파일을 앱 번들의 `Contents/Resources/web/`으로 변경 사항 발생 시 즉시 동기화 복사.
