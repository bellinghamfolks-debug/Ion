# EnglishNova Server

Backend for the EnglishNova app: **accounts**, **auth** (email/password + Sign in
with Apple) and **progress sync**, backed by **PostgreSQL**. Node.js + Express.

## Endpoints

| Method | Path             | Auth | Body                              | Returns |
|--------|------------------|------|-----------------------------------|---------|
| GET    | `/health`        | –    | –                                 | `{status:"ok"}` |
| POST   | `/auth/register` | –    | `{email,password,displayName?}`   | `{token,user}` |
| POST   | `/auth/login`    | –    | `{email,password}`                | `{token,user}` |
| POST   | `/auth/apple`    | –    | `{identityToken,displayName?}`    | `{token,user}` |
| GET    | `/me`            | ✔    | –                                 | `{user}` |
| GET    | `/progress`      | ✔    | –                                 | `{data,updatedAt}` |
| PUT    | `/progress`      | ✔    | `{data:{…}}`                      | `{updatedAt}` |

Auth = send `Authorization: Bearer <token>`. `data` is an opaque JSON snapshot
the app owns (session, points, streak, skills, vocabulary…). Last-write-wins by
`updatedAt`.

## Deploy on Railway

1. Create a new Railway project → **Deploy from GitHub repo** → pick this repo.
2. Set the service **Root Directory** to `server`.
3. Add the **PostgreSQL** plugin (New → Database → PostgreSQL). Railway injects
   `DATABASE_URL` automatically.
4. Add service **Variables**:
   - `JWT_SECRET` = a long random string
   - `APPLE_CLIENT_ID` = the app bundle id (`com.bellinghamfolks.englishnova`)
5. Deploy. Railway runs `npm start` (`node src/index.js`); the schema is created
   automatically on first boot.
6. Under **Settings → Networking**, generate a public domain. That HTTPS URL is
   your server URL — paste it into the app (Settings → الخادم).

Verify: open `https://<your-domain>/health` → `{"status":"ok"}`.

## Local dev

```bash
cd server
cp .env.example .env    # fill DATABASE_URL / JWT_SECRET
npm install
npm start
```

## Notes
- Sign in with Apple requires the iOS app to be **signed** with the
  `com.apple.developer.applesignin` entitlement and the matching App ID; it will
  not work in an unsigned sideloaded build. Email/password works regardless.
- The server enforces JSON, a 5 MB body limit, bcrypt password hashing (cost 12)
  and never returns password hashes.
