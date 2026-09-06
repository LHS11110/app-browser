# AppBrowser 문서 허브 (Documentation Hub)

AppBrowser 프로젝트의 구조와 설계 원리, 소스 코드에 대한 상세 기술 문서 모음입니다.

---

## 📑 문서 목록

| 문서명 | 주요 내용 | 링크 |
| :--- | :--- | :--- |
| **프로젝트 개요 및 구조 가이드** | 프로젝트 소개, 핵심 기능, 전체 디렉터리 트리, 빌드 및 실행 방법 | [overview.md](overview.md) |
| **시스템 아키텍처 및 설계 상세** | 멀티프로세스 분리 모델, CEF Views 프레임워크, IPC 통신 프로토콜, Dock 아이콘 합성 엔진, 정상 종료 파이프라인 | [architecture.md](architecture.md) |
| **프로세스 상호작용 및 저장소 구조** | 프로세스 간 통신(IPC) 시퀀스, action:// 프로토콜, LevelDB localStorage 그룹/메타데이터 스키마 및 무결성 규칙 | [inter_process_and_storage.md](inter_process_and_storage.md) |
| **소스 코드 상세 설명서** | C++/Objective-C++ 모든 소스 파일 및 함수별 설명, 웹 프론트엔드 리소스, CMake 빌드 시스템 구조 | [source_code_reference.md](source_code_reference.md) |

---

## 🚀 빠른 시작 (Quick Start)

```bash
# 1. 빌드
cmake --build build

# 2. 실행
open build/Release/AppBrowser.app
```
