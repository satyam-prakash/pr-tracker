# PR Tracker Client — Complete Documentation & Implementation Guide

This document serves as the complete description and architectural implementation guide for the **PR Tracker Client** project.

## 1. Complete Project Description

**PR Tracker** is a React-based frontend application designed to help developers and teams track GitHub pull requests across multiple repositories. It provides a centralized dashboard to view PR status, manage reviews, gain AI-powered code analysis, and monitor team workflows efficiently.

### Core Features

*   **GitHub OAuth Login**: Secure authentication using your GitHub account via a backend gateway.
*   **Repository Import & Tracking**: Select and import GitHub repositories. All PRs are instantly synchronized with the MongoDB backend.
*   **Pull Requests List**: Features a paginated table and Kanban view. Includes client-side filtering (by state: Open, Closed, Merged, Draft), searching, and sorting.
*   **Background Polling**: Pull requests automatically refresh every hour silently in the background while the page is open.
*   **Comprehensive PR Details**: Detailed view containing commits, changed files, inline code diffs, comments, and reviewer status.
*   **AI Code Review**: On-demand AI analysis of PR diffs, providing structured insights including a summary, identified issues, and actionable suggestions.
*   **Dashboard Analytics**: High-level statistical overview of tracked repositories and PR activities.

### Technology Stack

*   **UI Framework**: React 19
*   **Build Tool**: Vite 7
*   **Routing**: React Router v7
*   **Styling**: Tailwind CSS v4 (Utility-first CSS)
*   **API Client**: Axios
*   **Icons**: Lucide React
*   **Markdown Rendering**: `react-markdown` with `remark-gfm` and `rehype-raw`

---

## 2. Project Architecture & Folder Structure

The project is structured modularly around domains and features.

```text
src/
├── App.jsx                  # Application entry, Authentication wrapper, Routing setup
├── main.jsx                 # React root injection and strict mode
├── context/
│   └── RepoContext.jsx      # Global React Context handling active repos and users
├── components/
│   ├── layout/              # Structural wrappers
│   │   ├── AppLayout.jsx    # Main Layout wrapper (sidebar + main content)
│   │   ├── Header.jsx       # Top navigation
│   │   └── Sidebar.jsx      # Left navigation menu
│   ├── pages/               # Top-level route components
│   │   ├── Dashboard.jsx    # Application dashboard stats
│   │   ├── PullRequests.jsx # Main PR Listing page
│   │   ├── PRDetails.jsx    # Detailed view of a single PR
│   │   ├── Repository.jsx   # List of imported repositories
│   │   ├── ImportRepos.jsx  # Page to find and add new repos
│   │   ├── Login.jsx        # Login page UI
│   │   ├── LandingPage.jsx  # Public-facing landing page
│   │   └── AuthCallback.jsx # OAuth redirect handler
│   ├── features/            # Feature-specific isolated components
│   │   ├── PRs/             # Table, Kanban, Lists, Controls
│   │   ├── dashboard/       # Charts, Stat blocks
│   │   ├── repos/           # Modals and repo cards
│   │   └── AiSidebar.jsx    # AI Code insight tools
│   ├── shared/              # Components shared across multiple features
│   └── ui/                  # Smallest UI units (Buttons, Tags, etc.)
├── utils/
│   └── timeAgo.js           # Timestamp formatting utility
└── index.css                # Global CSS and Tailwind entry
```

---

## 3. Implementation Details

### A. Global State Management (`RepoContext.jsx`)
Instead of using Redux or Zustand, the app relies on a central React Context to store the logged-in user, the list of imported repositories, and the currently "active" repository being viewed. 

```javascript
// src/context/RepoContext.jsx
import { createContext, useContext, useState, useMemo } from "react";

const RepoContext = createContext();

export function RepoProvider({ children }) {
  const [activeRepository, setActiveRepository] = useState(null);
  const [activePr, setActivePr] = useState(null);
  const [repos, setRepos] = useState([]);
  const [user, setUser] = useState(null);
  const [refreshRepos, setRefreshRepos] = useState(() => () => { });

  const contextValue = useMemo(() => ({
    // ... expose state and setters
  }), [activeRepository, activePr, repos, user, refreshRepos]);

  return (
    <RepoContext.Provider value={contextValue}>
      {children}
    </RepoContext.Provider>
  );
}

export const useRepo = () => useContext(RepoContext);
```

### B. Routing and Data Initialization (`App.jsx`)
`App.jsx` handles initial application data load and renders `react-router` routes. The `AppContent` component fires a `loadData` function on mount which fetches user data and repository data via Axios and populates the `RepoContext`.

*   **Public Routes**: `/`, `/login`, `/auth/callback`
*   **Protected Routes**: Wrapped inside `<AppLayout />` (`/dashboard`, `/pull-requests`, `/repos`, etc.)

If a user has no imported repositories, the app sets a `needsImport` flag, guiding the user to the import page.

### C. The Pull Requests View (`PullRequests.jsx`)
This is the core functional page of the application. It fetches a paginated list of PRs from the backend using the active repository's data.

**Key Implementation Features:**
1.  **Pagination Strategy**: Supports backend pagination (`page`, `per_page`) combined with client-side filtering.
2.  **Hourly Polling**: Utilizes a `setInterval` hook that refreshes PR data automatically every 60 minutes.
3.  **View Modes**: Users can toggle between a standard `Table` view and a `Kanban` board.

```javascript
// Polling implementation inside PullRequests.jsx
useEffect(() => {
  if (!activeRepository?.owner || !activeRepository?.name) return;

  const POLL_INTERVAL_MS = 60 * 60 * 1000; // 1 hour
  const interval = setInterval(() => {
    fetchPRs(true, page);
  }, POLL_INTERVAL_MS);

  return () => clearInterval(interval);
}, [activeRepository, page, fetchPRs]);
```

### D. Authentication Flow
Authentication uses an OAuth flow with GitHub.
1. The user clicks **Login with GitHub** on the `/login` route.
2. They are redirected to the backend gateway to initiate the GitHub OAuth handshake.
3. Upon success, GitHub redirects to the backend callback, which securely sets an `httpOnly` JWT cookie.
4. The backend then redirects the frontend to `/auth/callback`, which pushes the user to `/dashboard`.
5. Every subsequent request made via Axios (`withCredentials: true`) includes this cookie for authorization.

### E. AI-Powered PR Insights
Within `PRDetails.jsx`, the user can request AI analysis. This triggers a backend endpoint that analyzes the `.patch` (diff) of the pull request using an LLM. The frontend then parses this data to generate:
*   An overarching summary.
*   A list of identified code smells, bugs, or security issues.
*   Specific optimization suggestions.

## 4. Environment Setup

To run this application locally, you must connect it to the `pr-tracker-service-router` backend.

1.  **Install Dependencies:** `npm install`
2.  **Environment Variables:** Create a `.env` file at the root:
    ```env
    VITE_SERVER_ENDPOINT=http://localhost:5000
    ```
3.  **Run Development Server:** `npm run dev`
    The application will spin up at `http://localhost:5173`.
