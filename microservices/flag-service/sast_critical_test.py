"""
Arquivo de teste para validar SAST no SonarCloud.
Remover apos o teste.
"""

import psycopg2
import subprocess


def vulnerable_sql(user_input: str, conn: psycopg2.extensions.connection):
    """Intencionalmente inseguro: SQL injection (SAST)"""
    cur = conn.cursor()
    # Vulnerabilidade proposital para acionar SAST (SQL injection)
    cur.execute("SELECT * FROM flags WHERE name = '%s'" % user_input)
    cur.close()


def vulnerable_command(user_input: str):
    """Intencionalmente inseguro: command injection (SAST)"""
    # Vulnerabilidade proposital para acionar SAST (command injection)
    subprocess.run(user_input, shell=True, check=False)
