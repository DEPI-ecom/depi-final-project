# Marketly — Application & Implementation Plan

**Status:** Proposed implementation baseline  
**Scope:** Customer-facing e-commerce features; admin/seller UI and workflows are deferred.  
**Architecture:** Node.js microservices, React frontend, PostgreSQL, API Gateway, and a GitHub monorepo.  
**Payment:** Mock payment only. No real payment provider, card details, or payment webhooks.

## 1. Project goals

Marketly is a student e-commerce platform whose main purpose is to provide a realistic application on which to demonstrate Docker, Docker Compose, GitHub Actions, Terraform, Ansible, Kubernetes, monitoring, and rollback.

Build and test the application locally first. Keep service boundaries, health checks, configuration, and tests suitable for containerization from the beginning, then introduce the DevOps stack incrementally.

### Customer features in scope

| Feature | Description | Priority |
|---|---|---|
| Registration/login | Register, log in, receive expiring access token | High |
| Browse products | Paginated list and category filtering | High |
| Product details | Description, images, price, current stock | High |
| Search | Keyword search and category/price filters | High |
| Cart | Add, update quantity, remove, show preliminary total | High |
| Checkout | Validate current prices and stock, create order | High |
| Mock payment | Simulate success or failure and record result | High |
| Order history | List the signed-in customer's orders | Medium |
| Order tracking | View order/payment status | Medium |
| Profile | View/update profile and manage saved addresses | Medium |

### Deferred/out of scope

- Admin/seller dashboards and admin CRUD screens.
- Real payment gateway integration, card entry/storage, refunds, payment-provider webhooks.
- Shipping-provider integration and live courier tracking.
- Reviews, wishlists, coupons, recommendations, notifications.
- Message broker/event streaming in the first version.
- Dedicated search engine in the first version.
- Production-grade distributed transactions.

Products can be inserted through seed scripts. Admin APIs/UI can be added later without changing the customer service boundaries.

## 2. GitHub organization and repository layout

The team has a GitHub Organization and a root repository containing all project directories. Treat this as a **monorepo**: one Git repository with multiple independently structured application directories.

```text
Marketly/                         # Root GitHub repository
├── ecom-web/
├── ecom-api-gateway/
├── ecom-user/
├── ecom-catalog/
├── ecom-search/
├── ecom-cart/
├── ecom-order/
├── ecom-payment/
├── ecom-deploy/
├── ecom-infra/
├── docs/
│   ├── app-plan.md
│   ├── API_doc.md
│   └── README.md
├── .github/
│   └── workflows/
│       └── ci.yml
├── .gitignore
└── README.md                     # Optional short GitHub landing page
```

Each service directory has its own `package.json`, source, tests, `.env.example`, README, and Dockerfile. A service does not need a separate Git repository to be a microservice: independence is about ownership, deployment, data, and communication boundaries.

**Monorepo consequences**
- One pull request can change multiple services.
- Use GitHub Actions path filters or a changed-service matrix so only affected services are tested/built when practical.
- Build and publish a separate container image per service.
- Keep integrated Compose and Kubernetes configuration in `ecom-deploy`.
- Keep Terraform and Ansible in `ecom-infra`.
- Do not use Git submodules for the initial setup.
- If the course later requires separate repositories, extract each directory into its own repository under the same GitHub Organization. API contracts and service boundaries remain the same.

## 3. Technology stack

| Area | Choice | Notes |
|---|---|---|
| Frontend | React + Vite | SPA |
| Frontend routing | React Router | Customer pages |
| Frontend HTTP | Axios (or fetch wrapper) | One configured client |
| Backend | Node.js 22 LTS + Express | JavaScript ES modules |
| Database | PostgreSQL | Separate logical database per data-owning service |
| ORM/migrations | Prisma | One schema and migration history per service |
| Authentication | JWT access tokens + bcrypt | Simple course-project approach |
| Validation | Zod or express-validator | Choose one and use consistently |
| API Gateway | Express + http-proxy-middleware | Single public backend entry point |
| Testing | Jest/Vitest + Supertest | Pick one test stack and standardize |
| Logging | Pino | Structured JSON |
| Metrics | prom-client | Prometheus exposition |
| Containers | Docker | One image per application |
| Local orchestration | Docker Compose | Integrated local environment |
| CI/CD | GitHub Actions | Test, build, publish, deploy |
| Registry | GitHub Container Registry (GHCR) | SHA-tagged images |
| Infrastructure | Terraform | Provision resources |
| Configuration | Ansible | Configure hosts |
| Orchestration | Kubernetes | Deploy, scale, recover |
| Monitoring | Prometheus + Grafana | Dashboards and alerts |

Use JavaScript rather than TypeScript unless the team already knows TypeScript. Keep dependency versions and lockfiles consistent. Use the same Node version in local development, CI, and Docker.

### Keep the first version simple

- REST/JSON for all service communication.
- One local PostgreSQL container/server with separate logical databases.
- PostgreSQL filtering/full-text search initially; no Meilisearch requirement.
- Synchronous internal HTTP calls; no RabbitMQ/Kafka initially.
- Mock payment service; no real provider.
- React Context for authentication; Redux is unnecessary for this scope.

## 4. Architecture and responsibilities

```text
Browser
  |
  v
React frontend (ecom-web)
  |
  | public HTTP/JSON
  v
API Gateway (ecom-api-gateway)
  |
  +--> User Service ------ users_db
  +--> Catalog Service --- catalog_db
  +--> Search Service ---- calls Catalog API
  +--> Cart Service ------ cart_db
  +--> Order Service ----- orders_db
  |        +--> Cart API
  |        +--> Catalog API
  |        +--> Mock Payment API
  |
  +--> Payment Service -- payments_db
```

The browser calls only the API Gateway. Internal service calls use Docker/Kubernetes DNS names and private service ports.

| Repository | Responsibility | Data ownership |
|---|---|---|
| `ecom-web` | Register/login, browse/search, product details, cart, checkout, orders, profile | None |
| `ecom-api-gateway` | Public routing, CORS, request ID, basic rate limiting and gateway logging | None |
| `ecom-user` | Registration, login, JWT issuance, profile, addresses | `users_db` |
| `ecom-catalog` | Products, categories, product details, stock validation/reservation/deduction | `catalog_db` |
| `ecom-search` | Search endpoint and filters; initially queries Catalog API | None initially |
| `ecom-cart` | Customer carts, cart items and preliminary totals | `cart_db` |
| `ecom-order` | Checkout orchestration, order snapshots, order history/status | `orders_db` |
| `ecom-payment` | Mock payment outcome and payment records | `payments_db` |
| `ecom-deploy` | Compose, Kubernetes manifests, monitoring config and deployment scripts | None |
| `ecom-infra` | Terraform modules/environments and Ansible inventories/playbooks | None |

### Service ownership rules

1. A service is the only application allowed to read/write its database.
2. Other services obtain data through that service's API, never by querying its tables.
3. No cross-service foreign keys.
4. Use IDs to refer to entities owned by another service.
5. Do not import another service's source code or ORM models.
6. Every backend service and the gateway exposes `/health` and `/metrics`.
7. Every service validates input and enforces authorization for its own protected routes. The gateway is not the only security boundary.

## 5. Database design

Use one PostgreSQL instance locally to reduce resource use, but create separate logical databases:

| Database | Owner | Initial tables |
|---|---|---|
| `users_db` | User | `users`, `addresses` |
| `catalog_db` | Catalog | `categories`, `products` |
| `cart_db` | Cart | `carts`, `cart_items` |
| `orders_db` | Order | `orders`, `order_items` |
| `payments_db` | Payment | `payments` |

### Suggested fields

**users:** `id` UUID, `name`, unique normalized `email`, `password_hash`, `role` (`CUSTOMER`; reserve `ADMIN` for later), timestamps.

**addresses:** `id`, `user_id` (UUID owned by User service), `label`, `recipient_name`, `phone`, `address_line`, `city`, `postal_code`, `country`, `is_default`, timestamps.

**categories:** `id`, `name`, `slug`, optional `description`.

**products:** `id`, `category_id`, `name`, `slug`, `description`, `price` (decimal), `image_url`, `stock_quantity`, `is_active`, timestamps.

**carts:** `id`, `user_id`, timestamps. Initially one active cart per customer.

**cart_items:** `id`, `cart_id`, `product_id`, `quantity`. A cart's displayed price is not authoritative.

**orders:** `id`, `user_id`, `status`, `subtotal`, `total`, `currency`, shipping-address snapshot fields, timestamps.

**order_items:** `id`, `order_id`, `product_id`, `product_name_snapshot`, `unit_price_snapshot`, `quantity`, `line_total`.

**payments:** `id`, `order_id`, `user_id`, `amount`, `currency`, `status` (`SUCCEEDED`/`FAILED`), unique `mock_reference`, optional `failure_reason`, timestamps.

Use decimal/numeric money values, not JavaScript floating-point calculations. Return money as decimal strings in JSON (for example `"129.99"`). Store only password hashes. Never store card numbers or CVV.

### Database/migration ownership

Each data-owning service has its own Prisma schema and migration history:

```text
ecom-user/prisma/schema.prisma
ecom-user/prisma/migrations/
ecom-catalog/prisma/schema.prisma
ecom-catalog/prisma/migrations/
...
```

Each container receives its own `DATABASE_URL`, pointing to its own database. Example:

```env
DATABASE_URL=postgresql://marketly:local_password@postgres:5432/users_db
```

For local Compose, one PostgreSQL initialization script can create all databases on first initialization. Note: scripts in `/docker-entrypoint-initdb.d/` run only when the data directory is initialized for the first time. If the init script changes after a named volume exists, create missing databases manually or deliberately recreate the development volume (this deletes its data).

## 6. Authentication and authorization

- Registration accepts name, email, password.
- Trim/lowercase email before checking uniqueness.
- Hash passwords with bcrypt.
- Login verifies the password and issues a signed, expiring JWT access token.
- Protected frontend requests send `Authorization: Bearer <token>`.
- Customer ID for user-owned data must come from the verified token, not a browser-supplied user ID.
- Initial role is `CUSTOMER`; keep the role field extensible for `ADMIN`.
- Each service verifies JWTs on its protected routes. For this course project, services may share a JWT verification secret through environment variables on the private application network. Document this as a simplification.
- Do not log tokens, passwords, or sensitive personal data.
- Refresh tokens and complex session management are out of scope initially.

## 7. Mock payment and checkout

Payment is a mock simulation. The checkout UI offers clearly labelled choices:
- `Simulate successful payment`
- `Simulate failed payment`

This is not a card form. Do not request/store card number, CVV, expiry date, or bank credentials. No external provider or webhook is involved.

### Checkout sequence

1. Customer sends checkout request to Order through the gateway.
2. Order retrieves the customer's cart from Cart.
3. Order asks Catalog to validate product availability and obtain current prices.
4. Order creates a `PENDING_PAYMENT` order and stores product/price/address snapshots.
5. Order calls Payment with order ID, amount, currency and requested mock outcome.
6. Payment records `SUCCEEDED` or `FAILED` and returns a generated mock reference.
7. On success, Order becomes `PAID`, Catalog confirms stock deduction, and Cart is cleared.
8. On failure, Order becomes `PAYMENT_FAILED`; cart remains available for retry.
9. Frontend displays the result and links to order details.

For this educational mock only, checkout may accept `mockPaymentOutcome: "SUCCESS" | "FAILURE"`. The UI must make it obvious this is simulated. A real payment integration must never trust the browser to declare that a payment succeeded.

### Reliability simplifications

- Require an `Idempotency-Key` on checkout and return the existing result for repeated submissions.
- Prevent more than one successful mock payment for the same order.
- Stock validation failure returns `409` and does not create a payable order.
- Payment failure leaves the order `PAYMENT_FAILED` and cart intact.
- If a service is unavailable, return a clear temporary error; never mark an order paid.
- A crash between steps can leave a `PENDING_PAYMENT` order. Provide a simple retry/recovery path and document it. A full Saga/outbox implementation is out of scope.

## 8. API Gateway

Public route mapping:

| Public path | Target |
|---|---|
| `/api/auth/*` | User |
| `/api/users/*` | User |
| `/api/products/*` | Catalog |
| `/api/categories/*` | Catalog |
| `/api/search/*` | Search |
| `/api/cart/*` | Cart |
| `/api/orders/*` | Order |
| `/api/payments/*` | Payment (only customer-safe payment history/status if exposed) |
| `/health` | Gateway |
| `/metrics` | Gateway |

Use Express and `http-proxy-middleware`. Gateway responsibilities: CORS for the frontend origin, request ID generation/forwarding, basic login/register rate limiting, structured request logs, forwarding Authorization, and consistent service-unavailable errors. Services still validate and authorize their own operations.

## 9. Standard backend structure

Use this template for User, Catalog, Cart, Order, and Payment. Search and Gateway use a lighter variant described below.

```text
ecom-<service>/
├── src/
│   ├── config/
│   │   ├── env.js
│   │   └── database.js          # data-owning services
│   ├── controllers/
│   ├── routes/
│   ├── services/
│   ├── middleware/
│   │   ├── auth.middleware.js
│   │   └── error.middleware.js
│   ├── validators/
│   ├── clients/                 # internal HTTP clients, where needed
│   ├── utils/
│   ├── app.js
│   └── server.js
├── prisma/                      # data-owning services only
│   ├── schema.prisma
│   └── migrations/
├── tests/
├── .env.example
├── .dockerignore
├── .gitignore
├── Dockerfile
├── package.json
├── package-lock.json
└── README.md
```

Responsibilities:
- `routes`: endpoint declarations and middleware wiring.
- `controllers`: parse request, call service, set response.
- `services`: business rules/orchestration.
- `models`: optional; Prisma can be used directly from service/repository modules.
- `middleware`: auth, errors, request logging.
- `validators`: request schema validation.
- `clients`: calls to other internal services.
- `config`: environment validation and DB setup.
- `app.js`: configure Express; do not call `listen`.
- `server.js`: initialize dependencies and listen.
- `tests`: unit and HTTP integration tests.

### Service-specific modules

**User**
```text
controllers/auth.controller.js
controllers/profile.controller.js
routes/auth.routes.js
routes/profile.routes.js
services/auth.service.js
services/profile.service.js
```

**Catalog**
```text
controllers/product.controller.js
controllers/category.controller.js
controllers/inventory.controller.js
routes/product.routes.js
routes/category.routes.js
services/product.service.js
services/inventory.service.js
```

**Search**
```text
controllers/search.controller.js
routes/search.routes.js
services/search.service.js
clients/catalog.client.js
```

**Cart**
```text
controllers/cart.controller.js
routes/cart.routes.js
services/cart.service.js
clients/catalog.client.js
```

**Order**
```text
controllers/order.controller.js
routes/order.routes.js
services/checkout.service.js
services/order.service.js
clients/cart.client.js
clients/catalog.client.js
clients/payment.client.js
```

**Payment**
```text
controllers/payment.controller.js
routes/payment.routes.js
services/mock-payment.service.js
```

### API Gateway structure

```text
ecom-api-gateway/
├── src/
│   ├── config/services.js
│   ├── routes/
│   │   ├── auth.routes.js
│   │   ├── users.routes.js
│   │   ├── products.routes.js
│   │   ├── search.routes.js
│   │   ├── cart.routes.js
│   │   ├── orders.routes.js
│   │   └── payments.routes.js
│   ├── middleware/
│   │   ├── cors.middleware.js
│   │   ├── request-id.middleware.js
│   │   └── error.middleware.js
│   ├── app.js
│   └── server.js
├── tests/
├── .env.example
├── .dockerignore
├── Dockerfile
├── package.json
└── README.md
```

### Search structure

```text
ecom-search/
├── src/
│   ├── controllers/search.controller.js
│   ├── routes/search.routes.js
│   ├── services/search.service.js
│   ├── clients/catalog.client.js
│   ├── app.js
│   └── server.js
├── tests/
├── .env.example
├── Dockerfile
├── package.json
└── README.md
```

## 10. Frontend structure

```text
ecom-web/
├── public/
├── src/
│   ├── assets/
│   ├── components/
│   │   ├── Navbar.jsx
│   │   ├── Footer.jsx
│   │   ├── ProductCard.jsx
│   │   ├── SearchBar.jsx
│   │   └── ProtectedRoute.jsx
│   ├── pages/
│   │   ├── Home.jsx
│   │   ├── Login.jsx
│   │   ├── Register.jsx
│   │   ├── Products.jsx
│   │   ├── ProductDetails.jsx
│   │   ├── Cart.jsx
│   │   ├── Checkout.jsx
│   │   ├── Orders.jsx
│   │   ├── OrderDetails.jsx
│   │   └── Profile.jsx
│   ├── services/
│   │   ├── api.js
│   │   ├── auth.service.js
│   │   ├── product.service.js
│   │   ├── cart.service.js
│   │   ├── order.service.js
│   │   └── payment.service.js
│   ├── context/AuthContext.jsx
│   ├── hooks/
│   ├── utils/
│   ├── App.jsx
│   ├── main.jsx
│   └── index.css
├── .env.example
├── .dockerignore
├── Dockerfile
├── index.html
├── package.json
└── vite.config.js
```

Frontend rules:
- Use one Axios instance configured with the gateway base URL.
- Attach JWT to protected requests.
- Show loading, empty, validation and error states.
- Never trust a frontend-calculated total at checkout.
- Label mock payment controls as simulation.
- Vite `VITE_` variables are public in the browser; never put secrets there.

## 11. Endpoint ownership summary

The complete endpoint contract, methods, request/response examples, and error codes are in `docs/API_doc.md`.

| Feature | Service |
|---|---|
| Register/login, profile, addresses | User |
| Product list/details/categories/stock | Catalog |
| Keyword and price/category search | Search |
| Cart CRUD and displayed total | Cart |
| Checkout, order history/details/status | Order |
| Simulated payment result/record | Payment |

## 12. Docker and deployment repository

Every application service owns its Dockerfile and `.dockerignore`. The integrated Compose file belongs in `ecom-deploy`.

```text
ecom-deploy/
├── docker/
│   ├── compose.yaml
│   ├── compose.dev.yaml
│   └── compose.prod.yaml
├── postgres/
│   └── init-databases.sql
├── kubernetes/
│   ├── namespace.yaml
│   ├── gateway/
│   ├── web/
│   ├── user/
│   ├── catalog/
│   ├── search/
│   ├── cart/
│   ├── order/
│   ├── payment/
│   ├── ingress.yaml
│   └── kustomization.yaml
├── monitoring/
│   ├── prometheus.yml
│   └── grafana/
├── scripts/
│   ├── start-local.sh
│   └── stop-local.sh
├── .env.example
└── README.md
```

### Dockerfile requirements

- Supported Node LTS slim image.
- `npm ci` and committed lockfile.
- Production start command.
- Non-root runtime user.
- Never copy `.env` or secrets into an image.
- `.dockerignore` excludes `node_modules`, `.git`, logs, local secrets and unnecessary files.
- Frontend uses a multi-stage build: Vite build with Node, static serving with Nginx.
- Expose application ports only. Do not expose database ports publicly in a production-like setup.

### Compose requirements

- Run frontend, gateway, six backend services, and PostgreSQL locally.
- Use one private application network and named database volumes.
- Publish frontend and gateway ports to the host; database port can be bound to `127.0.0.1` for local developer access only.
- Use service DNS names such as `http://ecom-user:3001`.
- Use health checks. `depends_on` without health conditions does not guarantee a database is ready.
- Use `.env.example`; real `.env` stays untracked.
- Add Prometheus/Grafana after the application stack is working.

## 13. GitHub Actions CI/CD

Because this is a monorepo, use path filters or a changed-directory matrix.

### Pull request CI
For changed services:
1. Checkout repository.
2. Set up matching Node version.
3. `npm ci`.
4. Run lint (if configured).
5. Run unit/integration tests.
6. Build frontend or backend.
7. Optionally build Docker image to validate Dockerfile.

Also validate:
- `docker compose config`
- Kubernetes YAML
- `terraform fmt -check` and `terraform validate`
- `ansible-playbook --syntax-check`

### Main branch image pipeline
1. Test changed service.
2. Build that service's image.
3. Tag with Git commit SHA.
4. Push to GHCR using `GITHUB_TOKEN` and package permissions.
5. Trigger/update deployment configuration.

Use immutable SHA tags rather than relying only on `latest`. Do not rebuild/deploy every service when only one service changes. Store deployment/cloud secrets in GitHub Actions Secrets/Environments. Pin actions to reviewed versions; full commit SHA pinning is preferred for stronger supply-chain security.

### Deployment/rollback
- Kubernetes Deployments use immutable image tags.
- Use rolling updates, readiness/liveness probes, resource requests/limits.
- Check rollout status after deployment.
- Demonstrate rollback with `kubectl rollout undo deployment/<name>`.
- Use approval environments if required.

## 14. Terraform and Ansible

```text
ecom-infra/
├── terraform/
│   ├── modules/
│   │   ├── vpc/
│   │   ├── compute/
│   │   ├── security-groups/
│   │   └── load-balancer/
│   ├── environments/
│   │   └── dev/
│   │       ├── main.tf
│   │       ├── variables.tf
│   │       ├── outputs.tf
│   │       └── terraform.tfvars.example
│   └── providers.tf
├── ansible/
│   ├── inventory/hosts.ini.example
│   ├── playbooks/
│   │   ├── setup-server.yml
│   │   ├── install-docker.yml
│   │   └── configure-kubernetes.yml
│   └── roles/
│       ├── docker/
│       └── monitoring/
└── README.md
```

Terraform provisions networking, compute, security groups and optionally a load balancer. Ansible configures provisioned hosts and installs required software. Kubernetes runs the application. GitHub Actions builds/publishes images and triggers deployment.

Choose a small course-approved environment. A small EC2-based Kubernetes cluster may demonstrate the concepts at lower complexity than a managed cluster, but document its limitations. Stop/destroy paid resources after demonstrations.

## 15. Kubernetes

Each stateless service should have:
- Deployment and ClusterIP Service.
- Resource requests and limits.
- Readiness and liveness probes using `/health`.
- ConfigMaps for non-secret configuration and Secrets for credentials.
- At least one replica initially; demonstrate scaling on selected services.
- Rolling update strategy.

Expose frontend and gateway through Ingress (or the course-approved ingress controller). Browser traffic still reaches the gateway as the single API entry point.

Database data requires persistent storage. A Kubernetes PostgreSQL StatefulSet/PVC can be used for a student demo, but a managed or separately hosted database is usually more appropriate for production. Never rely on ephemeral container storage for database data. HPA can demonstrate scaling for stateless services after metrics-server is installed; do not treat PostgreSQL as a stateless web service.

## 16. Monitoring and observability

Every backend service and gateway:
- `GET /health`: lightweight service health (optionally include dependency health).
- `GET /metrics`: Prometheus exposition using `prom-client`.

Use Pino structured JSON logs with timestamp, level, service, request ID, method, route, status, duration and safe error details. Never log credentials, tokens or sensitive personal data.

Useful metrics:
- HTTP request count by method/route/status.
- HTTP request duration histogram.
- Process CPU/memory.
- Optional business counters: checkout attempts, mock payment success/failure, stock conflicts.

Prometheus scrapes services; Grafana displays request rate, latency, error rate, resource use and service availability. Add an alert for high 5xx rate or unavailable service if time permits.

## 17. Quality and security requirements

- Hash passwords; never store plaintext.
- Validate request bodies, query parameters and IDs.
- Use Prisma/parameterized queries.
- Verify JWTs on protected routes.
- Restrict CORS to the frontend origin.
- Rate-limit authentication routes.
- Keep secrets out of Git, Docker images, logs and frontend bundles.
- No card details in mock payment.
- Paginate product and order lists.
- Index email, product slug/category, user ID, order ID and search fields as appropriate.
- Set timeouts on internal HTTP calls.
- Persist database data with volumes/PVCs.
- Store product/price/address snapshots in orders.
- Maintain `.env.example`, README, health checks and tests per service.

## 18. Recommended implementation order

1. Agree API contracts, status values, IDs, ownership and error format.
2. Create monorepo directories and minimal runnable service skeletons.
3. Set up PostgreSQL, separate databases, Prisma schemas and migrations.
4. Implement User (register/login/profile/addresses).
5. Implement Catalog (seed data, product/category list, details, stock).
6. Implement Search (keyword/category/price filters).
7. Implement Cart (CRUD and preliminary total).
8. Implement Order (checkout orchestration, snapshots, history/status).
9. Implement mock Payment (success/failure simulation and records).
10. Implement API Gateway and route all public traffic through it.
11. Implement React frontend and customer journeys.
12. Add integration tests, including failed payment and out-of-stock cases.
13. Add Dockerfiles and integrated Compose with persistent volumes.
14. Add GitHub Actions tests/builds and GHCR publishing.
15. Provision/configure infrastructure with Terraform and Ansible.
16. Deploy with Kubernetes; demonstrate probes, scaling, rolling update and rollback.
17. Add Prometheus, Grafana, logs, dashboards and alerts.

Add tests and health endpoints while implementing each service; do not postpone them to the end.

## 19. Definition of done

- Visitor can register and log in.
- Customer can browse paginated products/categories and search/filter.
- Product details show price and stock.
- Customer can add/update/remove cart items.
- Backend revalidates current prices and stock during checkout.
- Customer can simulate successful and failed payment.
- Success creates `PAID` order, updates stock and clears cart.
- Failure creates `PAYMENT_FAILED` order and retains cart for retry.
- Customer can view order history/status and manage profile/addresses.
- All browser API calls go through gateway.
- Each service owns its data and exposes `/health` and `/metrics`.
- Full stack runs through Compose with persistent DB volumes.
- CI tests changed services and images can be published to GHCR.
- Kubernetes deployment, probes, scaling and rollback are demonstrable.
- Terraform/Ansible provisioning/configuration is demonstrable.
- Prometheus/Grafana show useful metrics.

## 20. Assumptions to confirm

1. Root GitHub repository is a monorepo; folders are not separate Git repositories initially.
2. Customer features only; admin/seller workflows deferred.
3. Payment is mock-only; no external provider.
4. PostgreSQL is used for all persistent service data.
5. One local PostgreSQL instance hosts separate logical databases.
6. REST/JSON; no message broker in the first version.
7. Search initially uses Catalog API/PostgreSQL capabilities.
8. Seeded catalog data is enough for the initial release.
9. React SPA accesses backend only through gateway.
10. Team chooses one demo currency and consistent seed data.
11. Course budget/requirements determine cloud region and Kubernetes hosting approach.
12. This is an educational prototype, not a production commerce/payment platform.
