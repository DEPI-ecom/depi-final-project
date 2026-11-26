# Marketly

Marketly is a student e-commerce platform built to demonstrate software delivery and DevOps concepts using a Node.js microservices backend, React frontend, Docker, GitHub Actions, Terraform, Ansible, Kubernetes, Prometheus and Grafana.

**Payment is mock-only:** checkout can simulate success or failure. No real payment provider or card information is used.

## Onboarding

Run these commands to setup the repo structure:

git clone https://github.com/DEPI-ecom/Marketly.git

cd Marketly

./bootstrap.sh

## Project scope

Customer features:
- Register and log in.
- Browse paginated products and categories.
- View product details, price and stock.
- Search and filter products.
- Add/update/remove cart items.
- Checkout with server-side price and stock validation.
- Simulate successful or failed payment.
- View order history and order status.
- Update profile and saved addresses.

Admin/seller dashboards, real payment integration, shipping integration, and advanced commerce features are deferred.

## Repository layout

The project lives in one GitHub Organization root repository (monorepo):

```text
Marketly/
├── ecom-web/             # React + Vite frontend
├── ecom-api-gateway/     # Public API gateway
├── ecom-user/            # Auth, profile, addresses
├── ecom-catalog/         # Products, categories, stock
├── ecom-search/          # Search and filters
├── ecom-cart/            # Shopping cart
├── ecom-order/           # Checkout, order history/status
├── ecom-payment/         # Mock payment simulation
├── ecom-deploy/          # Docker Compose, Kubernetes, monitoring
├── ecom-infra/           # Terraform and Ansible
└── docs/
    ├── app-plan.md
    ├── API_doc.md
    └── README.md
```

Each service is an independently structured/deployable application directory, but not a separate Git repository. See `docs/app-plan.md` for architecture, ownership, assumptions, and detailed structures. See `docs/API_doc.md` for the endpoint contract.

## Technologies

- Frontend: React, Vite, React Router, Axios.
- Backend: Node.js 22 LTS, Express, JavaScript ES modules.
- Database: PostgreSQL; separate logical database per data-owning service.
- ORM: Prisma.
- Auth: JWT access token, bcrypt.
- Gateway: Express, `http-proxy-middleware`.
- Testing: Jest or Vitest + Supertest (standardize as a team).
- Containers: Docker and Docker Compose.
- CI/CD: GitHub Actions; images published to GHCR.
- Infrastructure: Terraform and Ansible.
- Orchestration: Kubernetes.
- Monitoring: Prometheus, Grafana; Pino logs and `prom-client` metrics.

## Architecture rules

1. The browser calls only the API Gateway.
2. Each data-owning service owns its database. No service directly queries another service's tables.
3. Services communicate over internal REST APIs.
4. Each backend service exposes `/health` and `/metrics`.
5. Checkout revalidates price and stock on the backend. Browser totals are display-only.
6. Orders store product name/price and shipping-address snapshots.
7. Mock payment does not collect or store card data.
8. Never commit `.env` files, passwords, JWT secrets, cloud keys, or Terraform state.

## Prerequisites

For local application development:
- Git.
- Node.js 22 LTS and npm.
- PostgreSQL (or Docker Desktop with Docker Compose).
- A code editor such as VS Code.

For the later DevOps stages:
- Docker Desktop / Docker Engine with Compose.
- GitHub Organization repository access.
- GitHub Container Registry permissions.
- Terraform and Ansible.
- `kubectl` and a Kubernetes cluster.
- Prometheus/Grafana deployment configuration.

Exact versions and cloud requirements should be recorded by the team and kept consistent.

## Initial setup

Clone the root repository:

```bash
git clone <GITHUB_ORG_REPOSITORY_URL>
cd Marketly
```

The following setup assumes each service has its own `package.json`. Replace directory names only if the team changes the agreed structure.

Install dependencies for a service:

```bash
cd ecom-user
npm ci
```

Repeat for the other Node services and `ecom-web`.

Create local environment files from examples:

```bash
# From the root directory, copy each service's example file.
# Linux/macOS:
cp ecom-user/.env.example ecom-user/.env
cp ecom-catalog/.env.example ecom-catalog/.env
cp ecom-cart/.env.example ecom-cart/.env
cp ecom-order/.env.example ecom-order/.env
cp ecom-payment/.env.example ecom-payment/.env
cp ecom-api-gateway/.env.example ecom-api-gateway/.env
cp ecom-search/.env.example ecom-search/.env
cp ecom-web/.env.example ecom-web/.env
```

On Windows PowerShell, use `Copy-Item <source> <destination>` for each file.

Edit local values. Do not commit the resulting `.env` files.

## Environment configuration

Each service must provide an `.env.example` documenting its required variables.

Typical backend variables:

```env
NODE_ENV=development
PORT=3001
DATABASE_URL=postgresql://marketly:local_password@localhost:5432/users_db
JWT_SECRET=replace-with-local-development-secret
JWT_EXPIRES_IN=1h
```

Service-to-service URLs should use localhost when running processes directly on the host, and Compose service DNS names when running inside Docker, for example:

```env
USER_SERVICE_URL=http://ecom-user:3001
CATALOG_SERVICE_URL=http://ecom-catalog:3002
CART_SERVICE_URL=http://ecom-cart:3004
ORDER_SERVICE_URL=http://ecom-order:3005
PAYMENT_SERVICE_URL=http://ecom-payment:3006
```

Frontend example:

```env
VITE_API_BASE_URL=http://localhost:8080/api
```

Vite variables prefixed with `VITE_` are bundled into browser code. Never put secrets in them.

The root Compose configuration should use a root/deployment `.env` or documented variable mechanism for PostgreSQL credentials. Keep `.env.example` placeholders only.

## Running locally before Docker

Start PostgreSQL and create the service databases:
- `users_db`
- `catalog_db`
- `cart_db`
- `orders_db`
- `payments_db`

Run each service's Prisma migrations and seed scripts as documented in that service's README. Example:

```bash
cd ecom-user
npx prisma migrate dev
npm run dev
```

Start backend services on the ports agreed in their `.env.example` files, then start the gateway and frontend. The frontend should call only the gateway.

Example scripts (each service should implement the relevant ones):

```bash
npm run dev
npm test
npm run build
npm start
npx prisma migrate dev
npx prisma db seed
```

Do not assume a script exists until it is added to that service's `package.json` and README.

## Running with Docker Compose

The integrated Compose file is maintained in `ecom-deploy/docker/compose.yaml`.

From the root repository, the exact command depends on the relative paths in that Compose file. A typical invocation is:

```bash
docker compose -f ecom-deploy/docker/compose.yaml --env-file ecom-deploy/.env up --build
```

Stop containers:

```bash
docker compose -f ecom-deploy/docker/compose.yaml --env-file ecom-deploy/.env down
```

Stop and delete database volumes (DESTRUCTIVE — deletes local database data):

```bash
docker compose -f ecom-deploy/docker/compose.yaml --env-file ecom-deploy/.env down -v
```

The Compose file must build each service using its repository directory as build context, put containers on a private network, use named volumes for PostgreSQL persistence, and include health checks. Only publish the frontend/gateway ports to the host; database ports should remain internal or be bound to loopback for local development.

## Mock payment behavior

At checkout the UI offers:
- Simulate successful payment.
- Simulate failed payment.

The Order service calls the internal Payment service. Payment records a mock success/failure and returns a generated mock reference. Successful payment results in a `PAID` order, stock update, and cleared cart. Failed payment results in `PAYMENT_FAILED`; the cart remains for retry.

This is only a course demonstration. Do not enter real card details. No card data is collected or stored.

## API

Local public API base URL:

```text
http://localhost:8080/api
```

Main route groups:
- `/auth`, `/users`
- `/products`, `/categories`
- `/search`
- `/cart`
- `/orders`
- `/payments` (only if a customer-safe payment status endpoint is exposed)

See `docs/API_doc.md` for methods, authentication, parameters, request/response examples, internal routes, health and metrics endpoints.

## Testing

Run tests in each changed service:

```bash
npm ci
npm test
```

Before merging, the team should verify:
- Register/login and protected route behavior.
- Product listing/details/search/filtering.
- Cart add/update/remove and ownership checks.
- Checkout rejects empty carts and insufficient stock.
- Successful mock payment creates a paid order, updates stock and clears cart.
- Failed mock payment creates a failed order and retains cart.
- A customer cannot read another customer's cart/orders/addresses.
- Health and metrics endpoints respond.
- Compose starts all dependencies and data persists after container recreation.

## DevOps workflow

Planned progression:

1. Application and API contracts.
2. Unit/integration tests.
3. Dockerfiles and Docker Compose.
4. GitHub Actions CI (test, lint, build).
5. Build and push service-specific images to GHCR using commit-SHA tags.
6. Terraform provisions the course environment.
7. Ansible configures hosts.
8. Kubernetes deploys services with Deployments, Services, Ingress, probes, resources and rolling updates.
9. Demonstrate scaling and rollback.
10. Prometheus/Grafana dashboards and alerts.

CI should use monorepo path filters or a changed-service matrix so unrelated services are not rebuilt unnecessarily.

## Security and secrets

- Never commit `.env`, credentials, private keys, cloud secrets, or Terraform state.
- Use GitHub Actions Secrets/Environments for deployment credentials.
- Hash passwords with bcrypt.
- Verify JWTs in protected services.
- Validate input and use Prisma/parameterized queries.
- Do not log passwords, tokens, or sensitive personal information.
- Restrict CORS to the frontend origin.
- Rate-limit registration/login.
- Keep database ports private.
- Do not collect card details for mock payments.

## Troubleshooting

**Service cannot connect to PostgreSQL**
- Confirm PostgreSQL is running and healthy.
- Check the database exists and the service's `DATABASE_URL` points to the correct database.
- Remember `localhost` inside a container means that same container. Use the Compose database service name (e.g. `postgres`) from containers.

**Service cannot reach another service**
- From a container, use the Compose service DNS name and internal port, not `localhost`.
- Confirm both containers are on the same Docker network.
- Check the target service health endpoint and configured URL.

**Prisma reports missing tables**
- Run that service's migrations against its own database.
- Confirm the service is not accidentally pointing at another service's database.

**Changed PostgreSQL init script did not create a database**
- Init scripts run only on first initialization of an empty data directory. Create the missing DB manually or deliberately recreate the local volume (data loss warning).

**Frontend requests fail**
- Confirm `VITE_API_BASE_URL` points to the gateway.
- Check gateway CORS settings and route targets.
- Inspect browser network tools and gateway logs.

**Port already in use**
- Change the local host port mapping or stop the process/container occupying it.

## Documentation

- `docs/app-plan.md` — complete architecture, responsibilities, technology choices, assumptions, repository structures, DevOps plan and implementation order.
- `docs/API_doc.md` — endpoint contracts, request/response examples, statuses and internal routes.
- Each service should also have a short README describing its own environment variables, scripts, migrations, tests and local port.
