// Runtime configuration validation for EnglishNova.
// Production fails closed for the database and session secret. Google Sign-In
// remains optional because the recovered build 50 reference does not configure it.

export function isProductionEnvironment(env = process.env) {
  return env.NODE_ENV === "production" ||
    Boolean(env.RAILWAY_ENVIRONMENT_ID) ||
    String(env.RAILWAY_ENVIRONMENT_NAME || "").toLowerCase() === "production" ||
    Boolean(env.K_SERVICE); // Cloud Run automatically exposes K_SERVICE.
}

function cloudSqlConfigured(env) {
  return Boolean(
    String(env.INSTANCE_UNIX_SOCKET || "").trim() &&
    String(env.DB_USER || "").trim() &&
    String(env.DB_PASS || "") &&
    String(env.DB_NAME || "").trim()
  );
}

export function runtimeConfigStatus(env = process.env) {
  const databaseURL = String(env.DATABASE_URL || "").trim();
  const jwtSecret = String(env.JWT_SECRET || "").trim();
  const googleServerClientID = String(env.GOOGLE_SERVER_CLIENT_ID || "").trim();
  const production = isProductionEnvironment(env);

  return {
    production,
    databaseConfigured: databaseURL.length > 0 || cloudSqlConfigured(env),
    databaseMode: databaseURL.length > 0 ? "url" : (cloudSqlConfigured(env) ? "cloud-sql" : "missing"),
    sessionSecretConfigured: jwtSecret.length >= 32,
    googleConfigured: googleServerClientID.endsWith(".apps.googleusercontent.com"),
  };
}

export function validateRuntimeConfig(env = process.env) {
  const status = runtimeConfigStatus(env);
  const errors = [];

  if (!status.databaseConfigured) {
    errors.push("DATABASE_URL or Cloud SQL DB_USER/DB_PASS/DB_NAME/INSTANCE_UNIX_SOCKET is required");
  }

  if (status.production && !status.sessionSecretConfigured) {
    errors.push("JWT_SECRET must be at least 32 characters in production");
  }

  // Google Sign-In is optional for the recovered build. When configured, the
  // auth route validates tokens against GOOGLE_SERVER_CLIENT_ID; when absent,
  // email/password and the rest of the service remain available.

  return { status, errors };
}

export function assertRuntimeConfig(env = process.env) {
  const result = validateRuntimeConfig(env);
  if (result.errors.length > 0) {
    const error = new Error(`Invalid EnglishNova runtime configuration: ${result.errors.join("; ")}`);
    error.code = "invalid_runtime_configuration";
    throw error;
  }
  return result.status;
}
