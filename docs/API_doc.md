# Marketly — API Documentation

**Version:** 1.0 proposed contract  
**Style:** REST + JSON  
**Public base URL:** `http://localhost:8080/api`  
**Payment:** Mock simulation only. No real gateway, card data, or provider webhooks.  
**Scope:** Customer-facing endpoints. Admin endpoints are deferred.

## 1. Conventions

- Browser calls only the API Gateway. Services communicate internally over private Docker/Kubernetes networking.
- `Content-Type: application/json`.
- UUID IDs; UTC ISO-8601 timestamps.
- Money is represented as decimal strings, e.g. `"49.95"`.
- Pagination: `page` default `1`; `limit` default `12`, maximum `50`.
- Protected endpoints require `Authorization: Bearer <accessToken>`.
- Checkout requires `Idempotency-Key: <unique-client-generated-value>`.
- All paths in this document are public gateway paths.
- Use a consistent response envelope:

```json
{
  "data": {},
  "meta": {}
}
```

For list responses, `meta` may contain `page`, `limit`, `total`, and `totalPages`.

### Error format

```json
{
  "error": {
    "code": "VALIDATION_ERROR",
    "message": "The request contains invalid fields.",
    "details": [
      { "field": "email", "message": "A valid email is required." }
    ],
    "requestId": "request-uuid"
  }
}
```

### HTTP status codes

| Code | Meaning |
|---|---|
| 200 | Successful read/update/action |
| 201 | Resource created |
| 204 | Successful delete, no body |
| 400 | Malformed request/validation failure |
| 401 | Missing, invalid or expired token |
| 403 | Authenticated but forbidden |
| 404 | Resource not found |
| 409 | Duplicate/conflict/insufficient stock/idempotency conflict |
| 422 | Semantically invalid operation (if adopted consistently) |
| 429 | Rate limit exceeded |
| 500 | Unexpected server error |
| 503 | Required service unavailable |

---

## 2. Authentication and user profile — User Service

### `POST /auth/register`
Public. Creates a customer account.

Request:
```json
{
  "name": "Alex Customer",
  "email": "alex@example.com",
  "password": "StrongPassword123!"
}
```

`201 Created`:
```json
{
  "data": {
    "user": {
      "id": "9d98f6c0-6d4a-4b8b-a3f3-5fbc83b0a2a0",
      "name": "Alex Customer",
      "email": "alex@example.com",
      "role": "CUSTOMER",
      "createdAt": "2026-11-26T10:00:00.000Z"
    }
  }
}
```

Errors: `400 VALIDATION_ERROR`, `409 EMAIL_ALREADY_EXISTS`. Hash password with bcrypt; never return the hash.

### `POST /auth/login`
Public.

Request:
```json
{ "email": "alex@example.com", "password": "StrongPassword123!" }
```

`200 OK`:
```json
{
  "data": {
    "accessToken": "<jwt>",
    "tokenType": "Bearer",
    "expiresIn": 3600,
    "user": {
      "id": "9d98f6c0-6d4a-4b8b-a3f3-5fbc83b0a2a0",
      "name": "Alex Customer",
      "email": "alex@example.com",
      "role": "CUSTOMER"
    }
  }
}
```

Errors: `400 VALIDATION_ERROR`, `401 INVALID_CREDENTIALS`.

### `GET /users/me`
Customer. Returns the authenticated user's profile.

`200 OK`:
```json
{
  "data": {
    "id": "user-uuid",
    "name": "Alex Customer",
    "email": "alex@example.com",
    "role": "CUSTOMER",
    "createdAt": "2026-11-26T10:00:00.000Z"
  }
}
```

### `PUT /users/me`
Customer. Updates editable profile fields.

Request:
```json
{ "name": "Alex C." }
```

Response: `200 OK` with updated user. Email changes can be omitted from the first release to avoid verification complexity.

### `GET /users/me/addresses`
Customer. Lists saved addresses.

### `POST /users/me/addresses`
Customer. Creates an address.

Request:
```json
{
  "label": "Home",
  "recipientName": "Alex Customer",
  "phone": "+201000000000",
  "addressLine": "12 Example Street",
  "city": "Giza",
  "postalCode": "12345",
  "country": "Egypt",
  "isDefault": true
}
```

Response: `201 Created` with the created address.

### `PUT /users/me/addresses/:addressId`
Customer. Updates an address owned by the authenticated customer. `200 OK`.

### `DELETE /users/me/addresses/:addressId`
Customer. Deletes an address owned by the authenticated customer. `204 No Content`.

Errors for address routes: `400`, `401`, `404`.

---

## 3. Catalog — Catalog Service

### `GET /products`
Public. Paginated product listing.

Query parameters:
- `page`, `limit`
- `categoryId` or `category` (choose one canonical parameter; recommended `categoryId`)
- `minPrice`, `maxPrice`
- `sort` (`name`, `price_asc`, `price_desc`, `newest`)

Example:
`GET /products?page=1&limit=12&categoryId=category-uuid&minPrice=10&maxPrice=100`

`200 OK`:
```json
{
  "data": [
    {
      "id": "product-uuid",
      "name": "Wireless Headphones",
      "description": "Over-ear wireless headphones",
      "price": "79.99",
      "imageUrl": "https://example.com/headphones.jpg",
      "stockQuantity": 14,
      "category": { "id": "category-uuid", "name": "Electronics" }
    }
  ],
  "meta": { "page": 1, "limit": 12, "total": 1, "totalPages": 1 }
}
```

### `GET /products/:productId`
Public. Returns product detail including description, image, price, category and stock. `404 PRODUCT_NOT_FOUND` if absent/inactive.

### `GET /categories`
Public. Returns available categories.

`200 OK`:
```json
{
  "data": [
    { "id": "category-uuid", "name": "Electronics", "slug": "electronics" }
  ]
}
```

### Internal catalog endpoints (service-to-service only)

These should not be exposed through the public gateway unless explicitly required.

- `POST /internal/stock/validate` — validate a list of product IDs and quantities and return current price/availability.
- `POST /internal/stock/reserve` — reserve stock for an order if implementing reservations.
- `POST /internal/stock/confirm` — confirm/deduct stock after successful mock payment.
- `POST /internal/stock/release` — release reservation after failed payment.

Suggested validate request:
```json
{
  "items": [
    { "productId": "product-uuid", "quantity": 2 }
  ]
}
```

Suggested response:
```json
{
  "data": {
    "valid": true,
    "items": [
      {
        "productId": "product-uuid",
        "name": "Wireless Headphones",
        "unitPrice": "79.99",
        "availableQuantity": 14
      }
    ]
  }
}
```

If implementing a simpler version without explicit reservation, perform validation and atomic stock deduction only after mock payment success, with a second stock check before deduction. Document the race-condition limitation.

---

## 4. Search — Search Service

### `GET /search`
Public. Searches catalog products.

Query parameters:
- `q` optional keyword
- `categoryId` optional category filter
- `minPrice`, `maxPrice` optional numeric bounds
- `page`, `limit`
- `sort` (`relevance`, `price_asc`, `price_desc`, `newest`)

Example:
`GET /search?q=headphones&categoryId=category-uuid&minPrice=20&maxPrice=150&page=1&limit=12`

`200 OK`: same product summary and pagination format as `GET /products`.

If `q` is absent, return filtered products or reject with `400`; choose and document one behavior. Initial implementation can call Catalog's internal search/list endpoint and use PostgreSQL filtering/full-text search. No separate search database is required initially.

---

## 5. Cart — Cart Service

All endpoints require customer authentication. The service derives `userId` from the verified JWT.

### `GET /cart`
Returns the current customer's cart.

`200 OK`:
```json
{
  "data": {
    "id": "cart-uuid",
    "items": [
      {
        "id": "cart-item-uuid",
        "productId": "product-uuid",
        "quantity": 2,
        "product": {
          "name": "Wireless Headphones",
          "price": "79.99",
          "imageUrl": "https://example.com/headphones.jpg",
          "stockQuantity": 14
        },
        "lineTotal": "159.98"
      }
    ],
    "subtotal": "159.98",
    "currency": "USD"
  }
}
```

The product summary may be fetched from Catalog. Cart total is preliminary and must be recalculated at checkout.

### `POST /cart/items`
Adds a product or increases its existing quantity.

Request:
```json
{ "productId": "product-uuid", "quantity": 1 }
```

Response: `201 Created` or `200 OK` if updating an existing cart line. Return updated cart.

Errors: `400`, `404 PRODUCT_NOT_FOUND`, `409 INSUFFICIENT_STOCK`.

### `PUT /cart/items/:itemId`
Changes quantity.

Request:
```json
{ "quantity": 3 }
```

Response: `200 OK` with updated cart. Quantity must be a positive integer. A quantity of zero should use DELETE.

### `DELETE /cart/items/:itemId`
Removes a cart line. `204 No Content`.

### `DELETE /cart`
Clears the customer's cart. `204 No Content`. Used after successful checkout.

---

## 6. Orders and checkout — Order Service

All customer endpoints require authentication. A customer may only access their own orders.

### `POST /orders/checkout`
Creates an order and runs the mock checkout flow.

Headers:
```http
Authorization: Bearer <token>
Idempotency-Key: <unique-value>
Content-Type: application/json
```

Request:
```json
{
  "addressId": "address-uuid",
  "mockPaymentOutcome": "SUCCESS"
}
```

`mockPaymentOutcome` is `SUCCESS` or `FAILURE`. This field exists only for the educational mock flow and must be clearly labelled as a simulation in the UI. The Order service fetches the cart, current product prices and stock, and address details from their owning services. Never trust a client-supplied total or product price.

Successful mock payment: `201 Created`:
```json
{
  "data": {
    "order": {
      "id": "order-uuid",
      "status": "PAID",
      "subtotal": "159.98",
      "total": "159.98",
      "currency": "USD",
      "items": [
        {
          "productId": "product-uuid",
          "productName": "Wireless Headphones",
          "unitPrice": "79.99",
          "quantity": 2,
          "lineTotal": "159.98"
        }
      ],
      "createdAt": "2026-11-26T10:30:00.000Z"
    },
    "payment": {
      "id": "payment-uuid",
      "status": "SUCCEEDED",
      "mockReference": "MOCK-abc123"
    }
  }
}
```

Failed mock payment: return a created order with `PAYMENT_FAILED` status and a failed payment record. The API may use `201 Created` because the order and payment attempt were recorded; keep this consistent.

```json
{
  "data": {
    "order": {
      "id": "order-uuid",
      "status": "PAYMENT_FAILED",
      "total": "159.98",
      "currency": "USD"
    },
    "payment": {
      "id": "payment-uuid",
      "status": "FAILED",
      "mockReference": "MOCK-def456",
      "failureReason": "Simulated payment failure"
    }
  }
}
```

Errors:
- `400 VALIDATION_ERROR`
- `401 UNAUTHORIZED`
- `404 ADDRESS_NOT_FOUND` or `CART_NOT_FOUND`
- `409 EMPTY_CART`, `INSUFFICIENT_STOCK`, `IDEMPOTENCY_CONFLICT`
- `503 DEPENDENCY_UNAVAILABLE`

Retry behavior: for the initial version, define either `POST /orders/:orderId/retry-payment` with a new idempotency key and mock outcome, or require the customer to retry checkout from the retained cart. Recommended simpler choice: support retry on the existing failed order so it does not create duplicate orders. If implementing this route, validate that the order belongs to the customer and is `PAYMENT_FAILED`.

### `GET /orders`
Customer. Lists the authenticated customer's orders, newest first.

Query: `page`, `limit`, optional `status`.

`200 OK`:
```json
{
  "data": [
    {
      "id": "order-uuid",
      "status": "PAID",
      "total": "159.98",
      "currency": "USD",
      "createdAt": "2026-11-26T10:30:00.000Z"
    }
  ],
  "meta": { "page": 1, "limit": 12, "total": 1, "totalPages": 1 }
}
```

### `GET /orders/:orderId`
Customer. Returns order details, item snapshots, shipping snapshot, total, payment/order status. Only the owning customer may access it.

### `GET /orders/:orderId/status`
Customer. Returns a minimal status payload:
```json
{
  "data": {
    "orderId": "order-uuid",
    "status": "PAID",
    "updatedAt": "2026-11-26T10:35:00.000Z"
  }
}
```

Suggested order statuses for the initial project:
- `PENDING_PAYMENT`
- `PAID`
- `PAYMENT_FAILED`
- `CANCELLED`

Do not introduce shipping statuses such as `IN_TRANSIT` unless shipping/fulfilment is actually implemented. “Order tracking” in this scope means viewing the order's current processing/payment status.

---

## 7. Mock Payment — Payment Service

Payment service is internal to the application. A customer normally initiates payment through Order checkout, not by directly calling Payment.

### Internal `POST /internal/payments/mock`
Called by Order service.

Request:
```json
{
  "orderId": "order-uuid",
  "userId": "user-uuid",
  "amount": "159.98",
  "currency": "USD",
  "outcome": "SUCCESS"
}
```

Response:
```json
{
  "data": {
    "id": "payment-uuid",
    "orderId": "order-uuid",
    "status": "SUCCEEDED",
    "mockReference": "MOCK-abc123",
    "amount": "159.98",
    "currency": "USD"
  }
}
```

For `outcome: "FAILURE"`, record `FAILED` and return a safe reason such as `"Simulated payment failure"`.

Rules:
- Accept only `SUCCESS` or `FAILURE`.
- Generate the mock reference on the server.
- Do not accept card details.
- Do not expose this internal endpoint to browsers.
- Prevent duplicate successful mock payments for one order.
- Validate amount and order ID format.
- This is a simulation, not a secure payment processor.

### Optional customer-safe endpoint

`GET /payments/:paymentId` may be exposed through the gateway only if customers need payment status/history. Verify ownership using the authenticated user. Otherwise, expose payment information through `GET /orders/:orderId` and omit this public route.

---

## 8. Health and metrics — every backend service and gateway

### `GET /health`
No authentication. Lightweight liveness/health response.

```json
{
  "status": "ok",
  "service": "ecom-user"
}
```

Optionally include dependency status for readiness, but avoid making liveness fail just because a downstream service is temporarily unavailable.

### `GET /metrics`
No user authentication on the internal network; do not expose publicly without protection. Returns Prometheus text exposition format, using `prom-client`.

Recommended metrics:
- HTTP request count by method/route/status.
- HTTP request duration histogram.
- Process metrics.
- Optional business counters for checkout, mock payment results and stock conflicts.

---

## 9. Internal service endpoints

These endpoints are private to the application network and should not be proxied publicly unless deliberately needed.

| Caller | Target | Endpoint | Purpose |
|---|---|---|---|
| Search | Catalog | `GET /internal/products/search` | Search/filter catalog |
| Cart | Catalog | `GET /internal/products/:id` | Validate product and show current summary |
| Order | Cart | `GET /internal/cart` | Retrieve customer's cart (forward trusted user identity/token) |
| Order | User | `GET /internal/users/:id/addresses/:addressId` | Validate and fetch address snapshot |
| Order | Catalog | `POST /internal/stock/validate` | Check stock and obtain current price |
| Order | Payment | `POST /internal/payments/mock` | Record mock payment outcome |
| Order | Catalog | `POST /internal/stock/confirm` | Deduct/confirm stock after success |
| Order | Cart | `DELETE /internal/cart` | Clear cart after success |

Implementation note: the exact internal authentication mechanism must be agreed before coding. For this course prototype, forward the verified customer JWT between trusted internal calls and have target services verify it, or use a narrowly scoped internal service token. Do not blindly trust a user ID header supplied by the public browser.

---

## 10. Endpoint summary

| Method | Path | Auth | Service |
|---|---|---|---|
| POST | `/auth/register` | Public | User |
| POST | `/auth/login` | Public | User |
| GET | `/users/me` | Customer | User |
| PUT | `/users/me` | Customer | User |
| GET | `/users/me/addresses` | Customer | User |
| POST | `/users/me/addresses` | Customer | User |
| PUT | `/users/me/addresses/:addressId` | Customer | User |
| DELETE | `/users/me/addresses/:addressId` | Customer | User |
| GET | `/products` | Public | Catalog |
| GET | `/products/:productId` | Public | Catalog |
| GET | `/categories` | Public | Catalog |
| GET | `/search` | Public | Search |
| GET | `/cart` | Customer | Cart |
| POST | `/cart/items` | Customer | Cart |
| PUT | `/cart/items/:itemId` | Customer | Cart |
| DELETE | `/cart/items/:itemId` | Customer | Cart |
| DELETE | `/cart` | Customer | Cart |
| POST | `/orders/checkout` | Customer | Order |
| GET | `/orders` | Customer | Order |
| GET | `/orders/:orderId` | Customer | Order |
| GET | `/orders/:orderId/status` | Customer | Order |
| GET | `/health` | Internal/public as configured | Each service |
| GET | `/metrics` | Internal only | Each service |

---

## 11. Contract decisions developers must keep consistent

Before implementation, agree on:
1. Whether responses always use `{ "data": ... }` and how list pagination metadata is represented.
2. Exact query parameter names (`categoryId`, `minPrice`, `maxPrice`, etc.).
3. Exact order/payment status enum values.
4. Whether failed checkout creates a `PAYMENT_FAILED` order (recommended) and how retry works.
5. Whether stock is reserved before mock payment or rechecked and deducted after success.
6. How internal service calls authenticate the customer/service identity.
7. Currency and decimal precision.
8. Whether `GET /payments/:paymentId` is needed publicly.

Update this document when the agreed contract changes; do not let each service invent its own incompatible response shape.
