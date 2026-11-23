-- Tabla de sesiones PHP para el despliegue en Vercel (vercel/bootstrap.php).
-- No pertenece al modelo de datos del SRS: solo guarda la sesión web del frontend.
CREATE TABLE IF NOT EXISTS php_sesion (
    id          VARCHAR(128) PRIMARY KEY,
    data        TEXT NOT NULL,
    actualizado TIMESTAMPTZ NOT NULL DEFAULT now()
);
GRANT SELECT, INSERT, UPDATE, DELETE ON php_sesion TO canariapp;
