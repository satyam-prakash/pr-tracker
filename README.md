# PR Tracker — Complete Project Description

**PR Tracker** is a comprehensive, microservices-based full-stack application designed to help developers and teams track GitHub pull requests across multiple repositories. It provides a centralized dashboard to view PR status, manage reviews, gain AI-powered code analysis, and monitor team workflows efficiently.

## Core Features
*   **GitHub OAuth Login**: Secure authentication using your GitHub account via a dedicated auth microservice.
*   **Repository Import & Tracking**: Select and import GitHub repositories. All PRs are instantly synchronized with the MongoDB backend.
*   **Pull Requests List & Kanban**: Features a paginated table and Kanban view. Includes client-side filtering (by state: Open, Closed, Merged, Draft), searching, and sorting.
*   **Background Polling**: Pull requests are automatically refreshed via a dedicated background poller (hourly or via k8s cronjob) and background client-side refreshing.
*   **Comprehensive PR Details**: Detailed view containing commits, changed files, inline code diffs, comments, and reviewer status.
*   **AI Code Review**: On-demand AI analysis of PR diffs using Mistral AI, providing structured insights including a summary, identified issues, and actionable suggestions.
*   **Microservices Architecture**: Highly scalable architecture with dedicated services for authentication, database operations, AI integration, and core logic.

## System Architecture

The project is structured into 8 independent services, orchestrated via Docker Compose for local/EC2 deployments and Kubernetes for production.

1. **NGINX Reverse Proxy (`nginx`)**
   - Routes incoming requests to the client and gateway.
   - Entry point for the application.

2. **React Frontend (`pr-tracker-client`)**
   - **Tech**: React 19, Vite 7, Tailwind CSS v4, React Router v7.
   - **Role**: Provides the user interface, state management via Context API, and communicates with the backend gateway.

3. **API Gateway (`pr-tracker-service-router`)**
   - **Role**: Centralized router (Port 5003) that acts as the entry point for API requests from the frontend, securely routing them to the appropriate microservices (Auth, Core, AI, DB).

4. **Auth Service (`pr-tracker-backend`)**
   - **Role**: Handles GitHub OAuth flow, user sessions, and issues JWT tokens. (Port 5005).

5. **Main Core Backend (`pr-tracker-main-backend`)**
   - **Role**: The core business logic. Communicates with GitHub API to fetch repositories, PRs, and commits. (Port 5002).

6. **AI Agent (`pr-tracker-ai-agent`)**
   - **Role**: Interacts with Mistral AI to analyze PR `.patch` diffs and generate automated code reviews. (Port 5001).

7. **MongoDB Data Service (`pr-tracker-mongodb`)**
   - **Role**: Dedicated data-access layer wrapping MongoDB interactions, ensuring secure and isolated database operations. (Port 5004).

8. **Background Poller (`pr-tracker-poller`)**
   - **Role**: A background worker that periodically polls GitHub to keep tracked PRs in sync. Deployed as a continuous worker in Docker Compose or a CronJob in Kubernetes.

## Deployment & DevOps
- **Containerization**: All services are containerized and images are published to GHCR.
- **Docker Compose**: `docker-compose.yml` provides a full-stack environment for local development and EC2 deployment.
- **Kubernetes**: The `k8s` directory contains manifests for deploying the microservices to a Kubernetes cluster.
- **Monitoring**: Supported by additional configurations in `docker-compose.monitoring.yml`.

## Getting Started (Local Development)

1. Clone the repository and install dependencies in the respective service directories.
2. Ensure you have Docker and Docker Compose installed.
3. Configure environment variables in `.env` (using `.env.example` as a template). Ensure GitHub OAuth and Mistral AI keys are provided.
4. Run the full stack using Docker Compose:
   ```bash
   docker-compose up --build
   ```
5. Access the application via `http://localhost`.
