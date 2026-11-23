#!/usr/bin/env python3
"""Cadena del nomenclador 2026: PDF -> CSV literal -> correcciones -> CSV canónico -> seed SQL.

Uso (desde cualquier carpeta):
    python3 catalogo/extraer.py
    python3 catalogo/extraer.py --solo-v7_1   # solo el seed v7.1, desde variedad_2026.csv (sin pdftotext)

Regenera TODO lo que está aguas abajo de los PDF. Nada de lo generado se edita a mano:
si algo está mal, se corrige en correcciones.csv (o en este script) y se vuelve a correr.

    fuente/*.pdf                       entrada (no se tocan; se verifica su SHA-256)
    correcciones.csv                   entrada (la única que se edita a mano)
    extraccion_literal_2026.csv        generado: lo que dice el PDF, sin corregir nada
    agrupaciones_2026.csv              generado: las 440 filas D.xxx-D.yyy (no son variedades)
    variedad_2026.csv                  generado: catálogo canónico (literal + correcciones aprobadas)
    seeds/variedad_2026.sql            generado: carga de serie y variedad, esquema v7.2 (SRS-RF010)
    seeds/variedad_2026_v7_1.sql       generado: la misma carga para el esquema v7.1 (serie como texto)
    Catalogo_CanariApp_2026.xlsx       generado: vista para que el cliente revise

Si alguna validación falla, el script termina con código 1 y no escribe nada.
Requiere pdftotext (poppler). Solo usa la biblioteca estándar de Python.
"""
import csv
import hashlib
import io
import re
import subprocess
import sys
import unicodedata
import zipfile
from collections import Counter, defaultdict
from datetime import date
from pathlib import Path
from xml.sax.saxutils import escape

DIR = Path(__file__).resolve().parent
FUENTE = DIR / 'fuente'

PDF_COLOR = FUENTE / '17768844458.pdf'
PDF_PORTE = FUENTE / 'e - 2026.pdf'
PAGINAS_COLOR = range(1, 28)   # 1-27
PAGINAS_PORTE = range(1, 48)   # 1-47; 48-188 no tienen texto de catálogo

# Valores esperados (revisión del nomenclador del 2026-11-09). Si el PDF cambia, el script falla
# a propósito: hay que revisar el nuevo PDF y actualizar estas cifras conscientemente.
ESPERADO = {
    'CC': 881, 'CP': 1780, 'E1': 1387, 'E2': 393,
    'agrupaciones': 440, 'series_CC': 98, 'series_CP': 38, 'en_estudio': 3,
}
LARGO_CODIGO, LARGO_NOMBRE, LARGO_SERIE = 10, 150, 100   # = columnas de la base

# Razas cuyos nombres empiezan con otra forma del encabezado (el Crest corona se
# llama «Crested» en el PDF). Se usa solo para validar, no cambia ningún dato.
PREFIJO_ALTERNATIVO = {'CREST': ('CRESTED (CORONA)',)}

APROBADOR_PENDIENTE = ''   # aprobado_por vacío = pendiente: se registra pero NO se aplica

# ---------------------------------------------------------------------------
# 1. Extracción literal
# ---------------------------------------------------------------------------
# Líneas que se ignoran (portada y encabezado de página). Cualquier otra línea que no
# sea código, agrupación o encabezado de serie hace fallar la extracción: así un cambio
# de formato del PDF no se pierde en silencio.
IGNORAR_COLOR = re.compile(r'^\s*(NOMENCLAD\.OR|OFICIAL|2026|SECCIÓN "D\.": CANARIOS D\.E COLOR'
                           r'|NomenclaD\.or Oficial: Sección "D\." - Canarios D\.e Color)\s*$')
IGNORAR_PORTE = re.compile(r'^\s*NOMENCLADOR OFICIAL - PORTE 2026\s*$')

RE_D_GRUPO = re.compile(r'^\s*(D\.\d{3}-D\.\d{3})\s{2,}(\S.*?)\s*$')
RE_D_CODIGO = re.compile(r'^\s*(D\.+\d{3})\s{2,}(\S.*?)\s*$')        # D..881 entra literal
RE_D_SERIE = re.compile(r'^\s{4,}(Serie \S.*?)\s*$')
RE_E_CODIGO = re.compile(r'^(E[12]\.\d{4})\s{2,}(\S.*?)\s*$')
RE_E_RAZA = re.compile(r'^\s{4,}(\S.*?) // ANILLO: (\d+,\d+) mm\s*$')
RE_E_ESTUDIO = re.compile(r'^\s{4,}(RAZA EN ESTUDIO - \S.*?)\s*$')


def falla(msg):
    print(f'ERROR: {msg}', file=sys.stderr)
    sys.exit(1)


# Cualquier cosa con forma de código del nomenclador (D.001, D..881, E1.0001, E3.1234...)
RE_CUALQUIER_CODIGO = re.compile(r'\b(D\.+\d{3}|E\d\.\d{4})\b')


def paginas_pdf(pdf):
    r = subprocess.run(['pdfinfo', str(pdf)], capture_output=True, text=True, check=True)
    return int(re.search(r'^Pages:\s+(\d+)', r.stdout, re.M)[1])


def texto_pagina(pdf, pagina):
    r = subprocess.run(['pdftotext', '-layout', '-enc', 'UTF-8', '-f', str(pagina), '-l', str(pagina),
                        str(pdf), '-'], capture_output=True, text=True, check=True)
    return r.stdout.replace('\f', '\n')


def verificar_fuentes():
    esperado = {}
    for linea in (FUENTE / 'SHA256SUMS').read_text().splitlines():
        h, nombre = linea.split(None, 1)
        esperado[nombre.lstrip('*')] = h
    for pdf in (PDF_COLOR, PDF_PORTE):
        h = hashlib.sha256(pdf.read_bytes()).hexdigest()
        if esperado.get(pdf.name) != h:
            falla(f'{pdf.name} no coincide con fuente/SHA256SUMS. Si es un PDF nuevo del cliente, '
                  'revisarlo y actualizar SHA256SUMS y las cifras de ESPERADO.')


def extraer_color():
    filas, grupos, serie = [], [], None
    for p in PAGINAS_COLOR:
        for n, linea in enumerate(texto_pagina(PDF_COLOR, p).splitlines(), 1):
            if not linea.strip() or IGNORAR_COLOR.match(linea):
                continue
            if m := RE_D_GRUPO.match(linea):
                grupos.append({'fuente': PDF_COLOR.name, 'pagina': p, 'codigo': m[1],
                               'codigo_desde': m[1][:5], 'codigo_hasta': m[1][6:],
                               'nombre': m[2], 'serie': serie})
            elif m := RE_D_CODIGO.match(linea):
                filas.append({'fuente': PDF_COLOR.name, 'pagina': p, 'seccion': 'D',
                              'codigo': m[1], 'nombre': m[2], 'serie': serie, 'anillo': ''})
            elif m := RE_D_SERIE.match(linea):
                serie = m[1]
            else:
                falla(f'color p.{p} línea {n} no reconocida: {linea!r}')
    return filas, grupos


def extraer_porte():
    filas, serie, anillo = [], None, ''
    for p in PAGINAS_PORTE:
        for n, linea in enumerate(texto_pagina(PDF_PORTE, p).splitlines(), 1):
            if not linea.strip() or IGNORAR_PORTE.match(linea):
                continue
            if m := RE_E_CODIGO.match(linea):
                filas.append({'fuente': PDF_PORTE.name, 'pagina': p, 'seccion': m[1][:2],
                              'codigo': m[1], 'nombre': m[2], 'serie': serie, 'anillo': anillo})
            elif m := RE_E_RAZA.match(linea):
                serie, anillo = m[1], m[2]
            elif m := RE_E_ESTUDIO.match(linea):
                serie, anillo = m[1], ''
            else:
                falla(f'porte p.{p} línea {n} no reconocida: {linea!r}')
    # El resto del PDF (48 hasta la última página) no debe traer ningún código: si los
    # trae, el rango quedó corto. Se revisa página por página.
    for p in range(PAGINAS_PORTE.stop, paginas_pdf(PDF_PORTE) + 1):
        if RE_CUALQUIER_CODIGO.search(texto_pagina(PDF_PORTE, p)):
            falla(f'porte p.{p} tiene códigos: revisar PAGINAS_PORTE')
    return filas


# ---------------------------------------------------------------------------
# 2. Correcciones explícitas
# ---------------------------------------------------------------------------
COLUMNAS_CORR = ['codigo', 'campo', 'valor_pdf', 'valor_corregido', 'motivo', 'aprobado_por']


def leer_correcciones():
    with open(DIR / 'correcciones.csv', newline='', encoding='utf-8') as f:
        r = csv.DictReader(f)
        if r.fieldnames != COLUMNAS_CORR:
            falla(f'correcciones.csv debe tener las columnas {COLUMNAS_CORR}')
        return list(r)


def aplicar_correcciones(literal, correcciones):
    """Devuelve (filas corregidas, pendientes, confirmados).

    Cada fila de correcciones.csv se compara con el valor LITERAL del PDF (valor_pdf).
    Si no coincide, el PDF cambió y la corrección quedó obsoleta: se falla en vez de
    aplicarla a ciegas. Cada (código, campo) se corrige una sola vez.
    codigo vacío + campo serie = corrección del nombre de una serie completa.

    Estados de una fila (no hace falta una columna extra):
      aprobado_por vacío                          -> pendiente: se registra, no se aplica
      aprobado_por lleno, valor_corregido distinto -> corrección: se aplica
      aprobado_por lleno, valor_corregido = valor_pdf -> confirmado sin cambio: el dato
                                                     del PDF queda como está y la consulta
                                                     se da por cerrada"""
    filas = [dict(f, codigo_pdf=f['codigo'], corregido='') for f in literal]
    pendientes, confirmados, ya = [], [], set()
    for i, c in enumerate(correcciones, 2):
        campo, aprobada = c['campo'], c['aprobado_por'].strip() != APROBADOR_PENDIENTE
        if campo not in ('codigo', 'nombre', 'serie'):
            falla(f'correcciones.csv línea {i}: campo {campo!r} no válido')
        if c['codigo']:
            destino = [(f, l) for f, l in zip(filas, literal) if l['codigo'] == c['codigo']]
            if not destino:
                falla(f'correcciones.csv línea {i}: el código {c["codigo"]} no está en el PDF')
        elif campo == 'serie':
            destino = [(f, l) for f, l in zip(filas, literal) if l['serie'] == c['valor_pdf']]
        else:
            falla(f'correcciones.csv línea {i}: falta el código')
        if not destino or any(l[campo] != c['valor_pdf'] for _, l in destino):
            falla(f'correcciones.csv línea {i}: valor_pdf {c["valor_pdf"]!r} no coincide con el PDF')
        if not aprobada:
            pendientes.append(c)
            continue
        if not c['valor_corregido'].strip():
            falla(f'correcciones.csv línea {i}: aprobada sin valor_corregido (para dejar el dato '
                  'como está, repetir el valor_pdf en valor_corregido)')
        for f, l in destino:
            if (l['codigo'], campo) in ya:
                falla(f'correcciones.csv línea {i}: {l["codigo"]} ya tiene una fila aprobada de {campo}')
            ya.add((l['codigo'], campo))
        if c['valor_corregido'] == c['valor_pdf']:
            confirmados.append(c)
            continue
        for f, l in destino:
            f[campo] = c['valor_corregido']
            f['corregido'] = ' '.join(sorted(set(f['corregido'].split()) | {campo}))
    return filas, pendientes, confirmados


# ---------------------------------------------------------------------------
# 3. Catálogo canónico
# ---------------------------------------------------------------------------
def sexo_desde_nombre(nombre):
    """Misma regla que variedad.sexo en la base (palabra completa, sin mayúsculas)."""
    if re.search(r'\bMACHO\b', nombre, re.I):
        return 'M'
    if re.search(r'\bHEMBRA\b', nombre, re.I):
        return 'H'
    return ''


def sin_tildes(texto):
    return ''.join(ch for ch in unicodedata.normalize('NFD', texto) if unicodedata.category(ch) != 'Mn')


def canonico(filas):
    orden = {'CC': {}, 'CP': {}}
    salida = []
    for f in filas:
        tipo = 'CC' if f['seccion'] == 'D' else 'CP'
        clave = (f['seccion'], f['serie'])
        orden[tipo].setdefault(clave, len(orden[tipo]) + 1)
        salida.append({
            'codigo': f['codigo'], 'nombre': f['nombre'], 'tipo': tipo, 'seccion': f['seccion'],
            'serie': f['serie'], 'anillo_mm': f['anillo'].replace(',', '.'),
            'serie_orden': orden[tipo][clave],
            'en_estudio': 'true' if re.search(r'estudio', f['serie'], re.I) else 'false',
            'sexo': sexo_desde_nombre(f['nombre']),
            'fuente': f['fuente'], 'pagina': f['pagina'],
            'codigo_pdf': f['codigo_pdf'], 'corregido': f['corregido'],
        })
    return salida


def validar(canon, grupos, pendientes, confirmados):
    errores = []
    tipos = Counter(v['tipo'] for v in canon)
    secciones = Counter(v['seccion'] for v in canon)
    for clave, real in [('CC', tipos['CC']), ('CP', tipos['CP']), ('E1', secciones['E1']),
                        ('E2', secciones['E2']), ('agrupaciones', len(grupos)),
                        ('series_CC', len({v['serie'] for v in canon if v['tipo'] == 'CC'})),
                        ('series_CP', len({v['serie'] for v in canon if v['tipo'] == 'CP'})),
                        ('en_estudio', sum(v['en_estudio'] == 'true' for v in canon))]:
        if real != ESPERADO[clave]:
            errores.append(f'{clave}: se esperaban {ESPERADO[clave]} y hay {real}')

    dup = [c for c, n in Counter(v['codigo'] for v in canon).items() if n > 1]
    if dup:
        errores.append(f'códigos duplicados: {dup}')
    for v in canon:
        if not re.fullmatch(r'D\.\d{3}|E[12]\.\d{4}', v['codigo']):
            errores.append(f'{v["codigo"]}: formato de código inválido (¿falta una corrección?)')
        if len(v['codigo']) > LARGO_CODIGO:
            errores.append(f'{v["codigo"]}: código de más de {LARGO_CODIGO} caracteres')
        if len(v['nombre']) > LARGO_NOMBRE:
            errores.append(f'{v["codigo"]}: nombre de más de {LARGO_NOMBRE} caracteres')
        if not v['serie']:
            errores.append(f'{v["codigo"]}: sin serie')
        elif len(v['serie']) > LARGO_SERIE or re.search(r'[a-z]D\.|D\.[a-zD]|D\.(\s|$)', v['serie']):
            errores.append(f'serie inválida {v["serie"]!r} (¿artefacto "D."?)')
        # En porte, el nombre empieza con la raza (salvo las categorías en estudio).
        # Se compara sin tildes: varios encabezados llevan tilde y sus nombres no
        # (ARLEQUÍN / ARLEQUIN), y eso no se corrige. Detecta SALENTNO y REHILÄNDER;
        # CONCOPETE se busca aparte (línea siguiente).
        prefijos = (v['serie'],) + PREFIJO_ALTERNATIVO.get(v['serie'], ())
        if (v['tipo'] == 'CP' and v['en_estudio'] == 'false'
                and not any(sin_tildes(v['nombre']).startswith(sin_tildes(p) + ' ') for p in prefijos)):
            errores.append(f'{v["codigo"]}: el nombre {v["nombre"]!r} no empieza con la raza {v["serie"]!r}')
        if re.search(r'SALENTNO|CONCOPETE', v['nombre']):
            errores.append(f'{v["codigo"]}: errata conocida sin corregir: {v["nombre"]!r}')

    # Una serie = un tipo, una sección y un anillo
    por_serie = defaultdict(set)
    for v in canon:
        por_serie[v['serie']].add((v['tipo'], v['seccion'], v['anillo_mm'], v['serie_orden']))
    for s, valores in por_serie.items():
        if len(valores) > 1:
            errores.append(f'serie {s!r} con datos contradictorios: {valores}')

    # Nombres repetidos: solo se aceptan si cada código tiene una consulta pendiente
    # o confirmada sin cambio en su nombre
    consultados = {c['codigo'] for c in pendientes + confirmados if c['campo'] == 'nombre'}
    nombres = defaultdict(list)
    for v in canon:
        nombres[v['nombre']].append(v['codigo_pdf'])
    for nombre, codigos in nombres.items():
        if len(codigos) > 1 and not set(codigos) <= consultados:
            errores.append(f'nombre repetido sin consulta pendiente ni confirmada: {nombre!r} {codigos}')

    if errores:
        falla('validación del catálogo:\n  ' + '\n  '.join(dict.fromkeys(errores)))


# ---------------------------------------------------------------------------
# 4. Seed SQL
# ---------------------------------------------------------------------------
def q(texto):
    return 'NULL' if texto in ('', None) else "'" + str(texto).replace("'", "''") + "'"


def seed_sql(canon):
    sexos = Counter(v['sexo'] or 'NULL' for v in canon)
    n_series = len({(v['seccion'], v['serie']) for v in canon})
    valores = ',\n'.join(
        f"({n},{q(v['codigo'])},{q(v['nombre'])},{q(v['tipo'])},{q(v['seccion'])},{q(v['serie'])},"
        f"{v['anillo_mm'] or 'NULL'},{v['serie_orden']},{v['en_estudio']},{q(v['sexo'])})"
        for n, v in enumerate(canon, 1))
    return f"""-- =====================================================================
-- Carga del nomenclador 2026: tablas serie y variedad (SRS-RF008, SRS-RF010, DAT-005)
--
-- ARCHIVO GENERADO por catalogo/extraer.py desde variedad_2026.csv.
-- No se edita a mano: se corrige correcciones.csv y se vuelve a generar.
--
-- {len(canon)} variedades: {sum(v['tipo'] == 'CC' for v in canon)} de color (CC) y \
{sum(v['tipo'] == 'CP' for v in canon)} de porte (CP).
-- Sexo esperado según el nombre: {sexos['M']} M, {sexos['H']} H, {sexos['NULL']} sin sexo.
--
-- Uso (después de canarios_v7_2.sql), como dueño de las tablas:
--   psql -v ON_ERROR_STOP=1 -d canariapp_test -f catalogo/seeds/variedad_2026.sql
-- Con el rol de la aplicación falla: el paso 4 hace DELETE sobre serie y
-- permisos_v7_2.sql no lo autoriza (ver AVISO_BACKEND.md).
--
-- Se puede ejecutar varias veces: la carga actualiza por código (SRS-RF010).
--   * Variedades que ya no vienen en el archivo: NO se borran, porque puede
--     haber ejemplares que las usen. Se informan como «sobrantes».
--   * Series que ya no vienen en el archivo (por ejemplo, porque se corrigió
--     su nombre): se borran si quedaron sin variedades; si todavía tienen
--     variedades sobrantes, se conservan y se informan.
--   * Si un cambio de nombre cambia el sexo de una variedad,
--     trg_marcar_revision deja sus ejemplares en «Requiere revisión».
-- Al final comprueba los totales y que la base calculó el mismo sexo que el
-- CSV; si algo no coincide, revierte todo.
-- =====================================================================

BEGIN;

-- 1. Tabla temporal con el CSV completo. Desaparece al hacer COMMIT.
--    n es el orden de la fila en el PDF: con él los id nuevos salen en el
--    mismo orden en todas las máquinas.
CREATE TEMP TABLE carga_variedad (
    n             INT          NOT NULL UNIQUE,
    codigo        VARCHAR(10)  PRIMARY KEY,
    nombre        VARCHAR(150) NOT NULL,
    tipo          CHAR(2)      NOT NULL,
    seccion       VARCHAR(2)   NOT NULL,
    serie         VARCHAR(100) NOT NULL,
    anillo_mm     NUMERIC(3,2),
    serie_orden   INT          NOT NULL,
    en_estudio    BOOLEAN      NOT NULL,
    sexo_esperado CHAR(1)
) ON COMMIT DROP;

INSERT INTO carga_variedad VALUES
{valores};

-- 2. Series: una fila por serie de color o raza de porte. Se identifican por
--    (seccion, nombre). Se insertan en el orden del PDF (color y luego porte).
INSERT INTO serie (tipo, seccion, nombre, anillo_mm, orden)
SELECT tipo, seccion, serie, anillo_mm, serie_orden
  FROM carga_variedad
 GROUP BY tipo, seccion, serie, anillo_mm, serie_orden
 ORDER BY tipo, serie_orden
ON CONFLICT (seccion, nombre) DO UPDATE
   SET tipo = EXCLUDED.tipo, anillo_mm = EXCLUDED.anillo_mm, orden = EXCLUDED.orden
 WHERE (serie.tipo, serie.anillo_mm, serie.orden)
       IS DISTINCT FROM (EXCLUDED.tipo, EXCLUDED.anillo_mm, EXCLUDED.orden);

-- 3. Variedades: se insertan o se actualizan por código (SRS-RF010). El WHERE
--    evita reescribir filas que no cambiaron (y disparar sus triggers).
--    La columna sexo no se carga: la calcula la base desde el nombre.
INSERT INTO variedad (codigo, nombre, tipo, id_serie, en_estudio)
SELECT c.codigo, c.nombre, c.tipo, s.id_serie, c.en_estudio
  FROM carga_variedad c
  JOIN serie s ON s.seccion = c.seccion AND s.nombre = c.serie
 ORDER BY c.n
ON CONFLICT (codigo) DO UPDATE
   SET nombre = EXCLUDED.nombre, tipo = EXCLUDED.tipo,
       id_serie = EXCLUDED.id_serie, en_estudio = EXCLUDED.en_estudio
 WHERE (variedad.nombre, variedad.tipo, variedad.id_serie, variedad.en_estudio)
       IS DISTINCT FROM (EXCLUDED.nombre, EXCLUDED.tipo, EXCLUDED.id_serie, EXCLUDED.en_estudio);

-- 4. Series que ya no vienen en el archivo y quedaron vacías (por ejemplo, el
--    nombre anterior de una serie corregida): se borran para que no aparezcan
--    en el selector. Las que aún tienen variedades sobrantes se conservan.
DELETE FROM serie s
 WHERE NOT EXISTS (SELECT 1 FROM carga_variedad c
                    WHERE c.seccion = s.seccion AND c.serie = s.nombre)
   AND NOT EXISTS (SELECT 1 FROM variedad v WHERE v.id_serie = s.id_serie);

-- 5. Comprobaciones. Cualquier diferencia revierte la carga completa.
DO $$
DECLARE
    v_faltan          INT;
    v_sexo            INT;
    v_cc              INT;
    v_cp              INT;
    v_series_archivo  INT := (SELECT count(DISTINCT (seccion, serie)) FROM carga_variedad);
    v_series_base     INT := (SELECT count(*) FROM serie);
    v_series_carga    INT;
    v_series_vacias   INT;
    v_series_sobran   INT;
    v_orden_repetido  INT;
    v_sobrantes       INT;
BEGIN
    SELECT count(*) INTO v_faltan
      FROM carga_variedad c LEFT JOIN variedad v USING (codigo)
     WHERE v.id_variedad IS NULL;
    SELECT count(*) INTO v_sexo
      FROM carga_variedad c JOIN variedad v USING (codigo)
     WHERE v.sexo IS DISTINCT FROM c.sexo_esperado;
    SELECT count(*) FILTER (WHERE v.tipo = 'CC'), count(*) FILTER (WHERE v.tipo = 'CP')
      INTO v_cc, v_cp
      FROM carga_variedad c JOIN variedad v USING (codigo);
    -- Series del archivo presentes en la base
    SELECT count(*) INTO v_series_carga
      FROM serie s
     WHERE EXISTS (SELECT 1 FROM carga_variedad c WHERE c.seccion = s.seccion AND c.serie = s.nombre);
    -- Ninguna serie de la base puede quedar sin variedades
    SELECT count(*) INTO v_series_vacias
      FROM serie s WHERE NOT EXISTS (SELECT 1 FROM variedad v WHERE v.id_serie = s.id_serie);
    -- Dos series del mismo tipo con el mismo orden desordenarían el selector
    SELECT count(*) INTO v_orden_repetido
      FROM (SELECT tipo, orden FROM serie GROUP BY tipo, orden HAVING count(*) > 1) d;
    SELECT count(*) INTO v_sobrantes
      FROM variedad v WHERE NOT EXISTS (SELECT 1 FROM carga_variedad c WHERE c.codigo = v.codigo);
    v_series_sobran := v_series_base - v_series_carga;

    IF v_faltan > 0 THEN
        RAISE EXCEPTION 'Carga incompleta: % variedades del archivo no quedaron en la base', v_faltan;
    END IF;
    IF v_sexo > 0 THEN
        RAISE EXCEPTION 'El sexo calculado por la base no coincide con el CSV en % variedades', v_sexo;
    END IF;
    IF v_cc <> {ESPERADO['CC']} OR v_cp <> {ESPERADO['CP']} THEN
        RAISE EXCEPTION 'Se esperaban {ESPERADO['CC']} CC y {ESPERADO['CP']} CP; quedaron % y %', v_cc, v_cp;
    END IF;
    IF v_series_archivo <> {n_series} OR v_series_carga <> v_series_archivo THEN
        RAISE EXCEPTION 'Se esperaban {n_series} series del archivo en la base; el archivo trae % y la base tiene %',
            v_series_archivo, v_series_carga;
    END IF;
    IF v_series_vacias > 0 THEN
        RAISE EXCEPTION 'Quedaron % series sin variedades', v_series_vacias;
    END IF;

    IF v_sobrantes > 0 THEN
        RAISE WARNING 'Hay % variedades en la base que no vienen en este archivo (no se borran; lista abajo)', v_sobrantes;
    END IF;
    IF v_series_sobran > 0 THEN
        RAISE WARNING 'Hay % series que no vienen en este archivo y se conservan porque tienen variedades sobrantes', v_series_sobran;
    END IF;
    IF v_orden_repetido > 0 THEN
        RAISE WARNING 'Hay % posiciones de orden repetidas entre series del mismo tipo (lista abajo)', v_orden_repetido;
    END IF;
    RAISE NOTICE 'Nomenclador 2026 cargado: % CC, % CP; % series en la base (% del archivo, % sobrantes); % variedades sobrantes',
        v_cc, v_cp, v_series_base, v_series_carga, v_series_sobran, v_sobrantes;
END $$;

-- 6. Informe
-- Variedades que no vienen en este archivo (no se borran)
SELECT v.codigo, v.nombre, s.nombre AS serie,
       (SELECT count(*) FROM canario k WHERE k.id_variedad = v.id_variedad) AS ejemplares
  FROM variedad v JOIN serie s USING (id_serie)
 WHERE NOT EXISTS (SELECT 1 FROM carga_variedad c WHERE c.codigo = v.codigo)
 ORDER BY v.codigo;

-- Series con el mismo orden dentro de un tipo
SELECT tipo, orden, string_agg(nombre, ' | ' ORDER BY nombre) AS series
  FROM serie GROUP BY tipo, orden HAVING count(*) > 1 ORDER BY tipo, orden;

-- Ejemplares que la carga dejó en «Requiere revisión» (SRS-RF010)
SELECT count(*) AS ejemplares_en_revision FROM canario WHERE requiere_revision;

COMMIT;
"""


LARGO_SERIE_V7_1 = 50   # variedad.serie es VARCHAR(50) en canarios_v7_1.sql


def seed_sql_v7_1(canon):
    """Seed para el esquema v7.1: sin tabla serie; la serie va como texto en variedad.serie."""
    largas = [v['codigo'] for v in canon if len(v['serie']) > LARGO_SERIE_V7_1]
    if largas:
        falla(f'{len(largas)} series no caben en variedad.serie VARCHAR({LARGO_SERIE_V7_1}) '
              f'de la v7.1: {largas[:5]}')
    sexos = Counter(v['sexo'] or 'NULL' for v in canon)
    n_cc = sum(v['tipo'] == 'CC' for v in canon)
    n_cp = sum(v['tipo'] == 'CP' for v in canon)
    n_series = len({v['serie'] for v in canon})
    estudio = ', '.join(v['codigo'] for v in canon if v['en_estudio'] in (True, 'true'))
    valores = ',\n'.join(
        f"({n},{q(v['codigo'])},{q(v['nombre'])},{q(v['tipo'])},{q(v['serie'])},{q(v['sexo'])})"
        for n, v in enumerate(canon, 1))
    return f"""-- =====================================================================
-- Carga del nomenclador 2026 en el esquema v7.1 (SRS-RF008, SRS-RF010, DAT-005)
--
-- ARCHIVO GENERADO por catalogo/extraer.py desde variedad_2026.csv.
-- No se edita a mano: se corrige correcciones.csv y se vuelve a generar.
--
-- {len(canon)} variedades: {n_cc} de color (CC) y {n_cp} de porte (CP), en {n_series} series.
-- Sexo esperado según el nombre: {sexos['M']} M, {sexos['H']} H, {sexos['NULL']} sin sexo.
--
-- Es la misma carga que variedad_2026.sql (v7.2), adaptada a la tabla
-- variedad de canarios_v7_1.sql, que NO tiene tabla serie:
--   * La serie (o raza de porte) se guarda como texto en variedad.serie.
--   * No se guardan el anillo en mm, el orden de la serie ni en_estudio,
--     porque la v7.1 no tiene esas columnas. Las categorías en estudio
--     ({estudio}) se cargan como variedades normales y se
--     reconocen por su nombre («... EN ESTUDIO ...»).
--   * Orden del PDF: en una base nueva los id_variedad salen en el orden del
--     PDF (id 1 = D.001), así que ORDER BY id_variedad lo respeta, y las series
--     se ordenan con min(id_variedad).
--
-- Uso (después de canarios_v7_1.sql y permisos_v7_1.sql), en la base de
-- desarrollo, NO en la de pruebas_v7_1.sql (sus datos suponen id desde 1):
--   psql -v ON_ERROR_STOP=1 -d canariapp_dev -f catalogo/seeds/variedad_2026_v7_1.sql
-- Solo hace INSERT y UPDATE sobre variedad, así que también funciona con el
-- rol de la aplicación (permisos_v7_1.sql).
--
-- Se puede ejecutar varias veces: la carga actualiza por código (SRS-RF010).
--   * Variedades que ya no vienen en el archivo: NO se borran, porque puede
--     haber ejemplares que las usen. Se informan como «sobrantes».
--   * Si un cambio de nombre cambia el sexo de una variedad,
--     trg_marcar_revision deja sus ejemplares en «Requiere revisión».
-- Al final comprueba los totales y que la base calculó el mismo sexo que el
-- CSV; si algo no coincide, revierte todo.
-- =====================================================================

BEGIN;

-- 0. Este archivo es solo para la v7.1: en la v7.2 variedad ya no tiene la
--    columna serie y hay que usar variedad_2026.sql.
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                    WHERE table_schema = current_schema()
                      AND table_name = 'variedad' AND column_name = 'serie') THEN
        RAISE EXCEPTION 'variedad.serie no existe: este seed es para canarios_v7_1.sql (en la v7.2 use variedad_2026.sql)';
    END IF;
END $$;

-- 1. Tabla temporal con el CSV completo. Desaparece al hacer COMMIT.
--    n es el orden de la fila en el PDF: con él los id nuevos salen en el
--    mismo orden en todas las máquinas.
CREATE TEMP TABLE carga_variedad (
    n             INT          NOT NULL UNIQUE,
    codigo        VARCHAR(10)  PRIMARY KEY,
    nombre        VARCHAR(150) NOT NULL,
    tipo          CHAR(2)      NOT NULL,
    serie         VARCHAR({LARGO_SERIE_V7_1})  NOT NULL,
    sexo_esperado CHAR(1)
) ON COMMIT DROP;

INSERT INTO carga_variedad VALUES
{valores};

-- 2. Variedades: se insertan o se actualizan por código (SRS-RF010). El WHERE
--    evita reescribir filas que no cambiaron (y disparar sus triggers).
--    La columna sexo no se carga: la calcula la base desde el nombre.
INSERT INTO variedad (codigo, nombre, tipo, serie)
SELECT codigo, nombre, tipo, serie
  FROM carga_variedad
 ORDER BY n
ON CONFLICT (codigo) DO UPDATE
   SET nombre = EXCLUDED.nombre, tipo = EXCLUDED.tipo, serie = EXCLUDED.serie
 WHERE (variedad.nombre, variedad.tipo, variedad.serie)
       IS DISTINCT FROM (EXCLUDED.nombre, EXCLUDED.tipo, EXCLUDED.serie);

-- 3. Comprobaciones. Cualquier diferencia revierte la carga completa.
DO $$
DECLARE
    v_faltan     INT;
    v_sexo       INT;
    v_cc         INT;
    v_cp         INT;
    v_series     INT;
    v_sobrantes  INT;
BEGIN
    SELECT count(*) INTO v_faltan
      FROM carga_variedad c LEFT JOIN variedad v USING (codigo)
     WHERE v.id_variedad IS NULL
        OR (v.nombre, v.tipo, v.serie) IS DISTINCT FROM (c.nombre, c.tipo, c.serie);
    SELECT count(*) INTO v_sexo
      FROM carga_variedad c JOIN variedad v USING (codigo)
     WHERE v.sexo IS DISTINCT FROM c.sexo_esperado;
    SELECT count(*) FILTER (WHERE v.tipo = 'CC'), count(*) FILTER (WHERE v.tipo = 'CP'),
           count(DISTINCT v.serie)
      INTO v_cc, v_cp, v_series
      FROM carga_variedad c JOIN variedad v USING (codigo);
    SELECT count(*) INTO v_sobrantes
      FROM variedad v WHERE NOT EXISTS (SELECT 1 FROM carga_variedad c WHERE c.codigo = v.codigo);

    IF v_faltan > 0 THEN
        RAISE EXCEPTION 'Carga incompleta: % variedades del archivo no quedaron iguales en la base', v_faltan;
    END IF;
    IF v_sexo > 0 THEN
        RAISE EXCEPTION 'El sexo calculado por la base no coincide con el CSV en % variedades', v_sexo;
    END IF;
    IF v_cc <> {n_cc} OR v_cp <> {n_cp} THEN
        RAISE EXCEPTION 'Se esperaban {n_cc} CC y {n_cp} CP; quedaron % y %', v_cc, v_cp;
    END IF;
    IF v_series <> {n_series} THEN
        RAISE EXCEPTION 'Se esperaban {n_series} series; quedaron %', v_series;
    END IF;

    IF v_sobrantes > 0 THEN
        RAISE WARNING 'Hay % variedades en la base que no vienen en este archivo (no se borran; lista abajo)', v_sobrantes;
    END IF;
    RAISE NOTICE 'Nomenclador 2026 cargado (v7.1): % CC, % CP, % series; % variedades sobrantes',
        v_cc, v_cp, v_series, v_sobrantes;
END $$;

-- 4. Informe
-- Variedades que no vienen en este archivo (no se borran)
SELECT v.codigo, v.nombre, v.serie,
       (SELECT count(*) FROM canario k WHERE k.id_variedad = v.id_variedad) AS ejemplares
  FROM variedad v
 WHERE NOT EXISTS (SELECT 1 FROM carga_variedad c WHERE c.codigo = v.codigo)
 ORDER BY v.codigo;

-- Ejemplares que la carga dejó en «Requiere revisión» (SRS-RF010)
SELECT count(*) AS ejemplares_en_revision FROM canario WHERE requiere_revision;

COMMIT;
"""


def solo_seed_v7_1():
    """Regenera solo el seed v7.1 desde variedad_2026.csv (no necesita pdftotext)."""
    with open(DIR / 'variedad_2026.csv', newline='', encoding='utf-8') as f:
        canon = list(csv.DictReader(f))
    if not canon:
        falla('variedad_2026.csv está vacío')
    (DIR / 'seeds').mkdir(exist_ok=True)
    (DIR / 'seeds' / 'variedad_2026_v7_1.sql').write_text(seed_sql_v7_1(canon), encoding='utf-8')
    print(f'OK: seeds/variedad_2026_v7_1.sql generado con {len(canon)} variedades.')


# ---------------------------------------------------------------------------
# 5. Vista Excel (xlsx mínimo escrito con zipfile, sin dependencias)
# ---------------------------------------------------------------------------
def _col(n):
    s = ''
    while n:
        n, r = divmod(n - 1, 26)
        s = chr(65 + r) + s
    return s


def _hoja(filas, anchos):
    xml = ['<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
           '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
           '<sheetViews><sheetView workbookViewId="0"><pane ySplit="1" topLeftCell="A2" '
           'activePane="bottomLeft" state="frozen"/></sheetView></sheetViews><cols>']
    xml += [f'<col min="{i}" max="{i}" width="{w}" customWidth="1"/>' for i, w in enumerate(anchos, 1)]
    xml.append('</cols><sheetData>')
    for r, fila in enumerate(filas, 1):
        xml.append(f'<row r="{r}">')
        for c, valor in enumerate(fila, 1):
            ref, estilo = f'{_col(c)}{r}', ' s="1"' if r == 1 else ''
            if isinstance(valor, (int, float)) and not isinstance(valor, bool):
                xml.append(f'<c r="{ref}"{estilo}><v>{valor}</v></c>')
            elif valor not in (None, ''):
                xml.append(f'<c r="{ref}" t="inlineStr"{estilo}><is><t xml:space="preserve">'
                           f'{escape(str(valor))}</t></is></c>')
        xml.append('</row>')
    xml.append('</sheetData>')
    if len(filas) > 1:
        xml.append(f'<autoFilter ref="A1:{_col(len(filas[0]))}{len(filas)}"/>')
    xml.append('</worksheet>')
    return ''.join(xml)


def escribir_xlsx(ruta, hojas):
    """hojas: lista de (nombre, filas, anchos); la primera fila de cada hoja es el encabezado."""
    ns = 'http://schemas.openxmlformats.org'
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, 'w', zipfile.ZIP_DEFLATED) as z:
        z.writestr('[Content_Types].xml',
                   f'<?xml version="1.0" encoding="UTF-8"?><Types xmlns="{ns}/package/2006/content-types">'
                   '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
                   '<Default Extension="xml" ContentType="application/xml"/>'
                   '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
                   '<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>'
                   + ''.join(f'<Override PartName="/xl/worksheets/sheet{i}.xml" ContentType="application/'
                             'vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'
                             for i in range(1, len(hojas) + 1)) + '</Types>')
        z.writestr('_rels/.rels',
                   f'<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="{ns}/package/2006/relationships">'
                   f'<Relationship Id="rId1" Type="{ns}/officeDocument/2006/relationships/officeDocument" '
                   'Target="xl/workbook.xml"/></Relationships>')
        z.writestr('xl/workbook.xml',
                   f'<?xml version="1.0" encoding="UTF-8"?><workbook xmlns="{ns}/spreadsheetml/2006/main" '
                   f'xmlns:r="{ns}/officeDocument/2006/relationships"><sheets>'
                   + ''.join(f'<sheet name="{escape(n)}" sheetId="{i}" r:id="rId{i}"/>'
                             for i, (n, _, _) in enumerate(hojas, 1))
                   + '</sheets></workbook>')
        z.writestr('xl/_rels/workbook.xml.rels',
                   f'<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="{ns}/package/2006/relationships">'
                   + ''.join(f'<Relationship Id="rId{i}" Type="{ns}/officeDocument/2006/relationships/worksheet" '
                             f'Target="worksheets/sheet{i}.xml"/>' for i in range(1, len(hojas) + 1))
                   + f'<Relationship Id="rId{len(hojas) + 1}" Type="{ns}/officeDocument/2006/relationships/styles" '
                   'Target="styles.xml"/></Relationships>')
        z.writestr('xl/styles.xml',
                   f'<?xml version="1.0" encoding="UTF-8"?><styleSheet xmlns="{ns}/spreadsheetml/2006/main">'
                   '<fonts count="2"><font><sz val="11"/><name val="Calibri"/></font>'
                   '<font><b/><sz val="11"/><name val="Calibri"/></font></fonts>'
                   '<fills count="3"><fill><patternFill patternType="none"/></fill>'
                   '<fill><patternFill patternType="gray125"/></fill>'
                   '<fill><patternFill patternType="solid"><fgColor rgb="FFDDEBF7"/></patternFill></fill></fills>'
                   '<borders count="1"><border/></borders>'
                   '<cellStyleXfs count="1"><xf/></cellStyleXfs>'
                   '<cellXfs count="2"><xf/><xf fontId="1" fillId="2" applyFont="1" applyFill="1"/></cellXfs>'
                   '</styleSheet>')
        for i, (_, filas, anchos) in enumerate(hojas, 1):
            z.writestr(f'xl/worksheets/sheet{i}.xml', _hoja(filas, anchos))
    ruta.write_bytes(buf.getvalue())


def estado_correccion(c):
    if c['aprobado_por'].strip() == APROBADOR_PENDIENTE:
        return 'pendiente'
    return 'confirmado sin cambio' if c['valor_corregido'] == c['valor_pdf'] else 'aplicada'


def vista_cliente(canon, grupos, correcciones, pendientes, confirmados):
    series = {}
    for v in canon:
        s = series.setdefault((v['tipo'], v['serie_orden']), [v['tipo'], v['seccion'], v['serie'],
                                                             float(v['anillo_mm']) if v['anillo_mm'] else '',
                                                             0, v['codigo'], v['codigo']])
        s[4] += 1
        s[6] = v['codigo']
    tipos = Counter(v['tipo'] for v in canon)
    sexos = Counter(v['sexo'] or '-' for v in canon)
    resumen = [
        ['Dato', 'Valor'],
        ['Generado el', date.today().isoformat()],
        ['Generado por', 'catalogo/extraer.py (no editar este archivo: es una vista)'],
        ['Fuente color', f'{PDF_COLOR.name}, páginas 1-27'],
        ['Fuente porte', f'{PDF_PORTE.name}, páginas 1-47'],
        ['Variedades de color (CC)', tipos['CC']],
        ['Variedades de porte (CP)', tipos['CP']],
        ['Series de color', ESPERADO['series_CC']],
        ['Razas de porte (encabezados)', ESPERADO['series_CP']],
        ['Categorías en estudio', sum(v['en_estudio'] == 'true' for v in canon)],
        ['Variedades MACHO / HEMBRA / sin sexo', f"{sexos['M']} / {sexos['H']} / {sexos['-']}"],
        ['Agrupaciones (no se cargan como variedad)', len(grupos)],
        ['Correcciones aplicadas', len(correcciones) - len(pendientes) - len(confirmados)],
        ['Confirmadas sin cambio (queda el dato del PDF)', len(confirmados)],
        ['Consultas pendientes al cliente', len(pendientes)],
    ]
    hojas = [
        ('Resumen', resumen, [45, 70]),
        ('Pendientes cliente', [['Código', 'Campo', 'Valor en el PDF', 'Propuesta', 'Pregunta / motivo']]
         + [[c['codigo'], c['campo'], c['valor_pdf'], c['valor_corregido'], c['motivo']] for c in pendientes],
         [12, 10, 55, 40, 90]),
        ('Correcciones', [COLUMNAS_CORR + ['estado']]
         + [[c[k] for k in COLUMNAS_CORR] + [estado_correccion(c)] for c in correcciones],
         [12, 10, 50, 50, 80, 16, 22]),
        ('Series', [['Tipo', 'Sección', 'Serie o raza', 'Anillo (mm)', 'Variedades', 'Primer código',
                     'Último código']] + [series[k] for k in sorted(series)],
         [6, 8, 50, 11, 11, 13, 13]),
        ('Variedades', [['Código', 'Nombre', 'Tipo', 'Sección', 'Serie o raza', 'Anillo (mm)', 'Sexo',
                         'En estudio', 'Página PDF', 'Código en PDF', 'Corregido']]
         + [[v['codigo'], v['nombre'], v['tipo'], v['seccion'], v['serie'],
             float(v['anillo_mm']) if v['anillo_mm'] else '', v['sexo'],
             'sí' if v['en_estudio'] == 'true' else '', v['pagina'],
             v['codigo_pdf'] if v['codigo_pdf'] != v['codigo'] else '', v['corregido']] for v in canon],
         [10, 60, 6, 8, 45, 11, 6, 10, 11, 13, 12]),
        ('Agrupaciones', [['Agrupación', 'Desde', 'Hasta', 'Nombre', 'Serie (literal)', 'Página PDF']]
         + [[g['codigo'], g['codigo_desde'], g['codigo_hasta'], g['nombre'], g['serie'], g['pagina']]
            for g in grupos],
         [14, 8, 8, 60, 45, 11]),
    ]
    escribir_xlsx(DIR / 'Catalogo_CanariApp_2026.xlsx', hojas)


# ---------------------------------------------------------------------------
def escribir_csv(ruta, filas, columnas):
    with open(ruta, 'w', newline='', encoding='utf-8') as f:
        w = csv.DictWriter(f, fieldnames=columnas, lineterminator='\n')
        w.writeheader()
        w.writerows(filas)


def main():
    verificar_fuentes()
    color, grupos = extraer_color()
    literal = color + extraer_porte()
    correcciones = leer_correcciones()
    filas, pendientes, confirmados = aplicar_correcciones(literal, correcciones)
    canon = canonico(filas)
    validar(canon, grupos, pendientes, confirmados)

    # Todo validó: recién ahora se escribe.
    escribir_csv(DIR / 'extraccion_literal_2026.csv', literal,
                 ['fuente', 'pagina', 'seccion', 'codigo', 'nombre', 'serie', 'anillo'])
    escribir_csv(DIR / 'agrupaciones_2026.csv', grupos,
                 ['fuente', 'pagina', 'codigo', 'codigo_desde', 'codigo_hasta', 'nombre', 'serie'])
    escribir_csv(DIR / 'variedad_2026.csv', canon,
                 ['codigo', 'nombre', 'tipo', 'seccion', 'serie', 'anillo_mm', 'serie_orden',
                  'en_estudio', 'sexo', 'fuente', 'pagina', 'codigo_pdf', 'corregido'])
    (DIR / 'seeds').mkdir(exist_ok=True)
    (DIR / 'seeds' / 'variedad_2026.sql').write_text(seed_sql(canon), encoding='utf-8')
    (DIR / 'seeds' / 'variedad_2026_v7_1.sql').write_text(seed_sql_v7_1(canon), encoding='utf-8')
    vista_cliente(canon, grupos, correcciones, pendientes, confirmados)

    tipos = Counter(v['tipo'] for v in canon)
    sec = Counter(v['seccion'] for v in canon)
    sexos = Counter(v['sexo'] or '-' for v in canon)
    print(f"OK: {tipos['CC']} CC + {tipos['CP']} CP (E1 {sec['E1']}, E2 {sec['E2']}); "
          f"{len(grupos)} agrupaciones aparte; sexo M {sexos['M']}, H {sexos['H']}, sin {sexos['-']}; "
          f"{len(correcciones) - len(pendientes) - len(confirmados)} correcciones aplicadas, "
          f"{len(confirmados)} confirmadas sin cambio, {len(pendientes)} pendientes.")


if __name__ == '__main__':
    if sys.argv[1:] == ['--solo-v7_1']:
        solo_seed_v7_1()
    else:
        main()
