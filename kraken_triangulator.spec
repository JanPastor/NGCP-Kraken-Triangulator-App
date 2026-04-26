# -*- mode: python ; coding: utf-8 -*-
"""
kraken_triangulator.spec — PyInstaller Build Specification
============================================================
Packages the KrakenSDR Triangulator into a standalone Windows executable.

Build command:
    pyinstaller kraken_triangulator.spec --clean --noconfirm

Output:
    dist/KrakenSDR-Triangulator/   (one-folder distribution)
"""

import os

block_cipher = None
BASE = os.path.dirname(os.path.abspath(SPEC))

a = Analysis(
    [os.path.join(BASE, 'launcher.py')],
    pathex=[BASE],
    binaries=[],
    datas=[
        # Bundle the entire frontend (HTML/CSS/JS + vendored libraries)
        (os.path.join(BASE, 'app'), 'app'),
        # Bundle sample replay data (mock_bearings.json only — not raw logs)
        (os.path.join(BASE, 'data', 'mock_bearings.json'), os.path.join('data')),
        # Bundle the server module (needed for import)
        (os.path.join(BASE, 'server', 'kraken_server.py'), 'server'),
    ],
    hiddenimports=[
        # Flask and dependencies
        'flask',
        'flask_cors',
        'flask.json',
        'jinja2',
        'jinja2.ext',
        'markupsafe',
        'werkzeug',
        'werkzeug.serving',
        'werkzeug.debug',
        'itsdangerous',
        'click',
        'blinker',

        # HTTP requests (optional live proxy)
        'requests',
        'urllib3',
        'charset_normalizer',
        'certifi',
        'idna',

        # MAVLink upstream transmission (bundled per user decision)
        'pymavlink',
        'pymavlink.mavutil',
        'pymavlink.mavlink',
        'pymavlink.dialects',
        'pymavlink.dialects.v20',
        'pymavlink.dialects.v20.common',
        'pymavlink.dialects.v20.ardupilotmega',

        # Standard library modules that PyInstaller sometimes misses
        'json',
        'socket',
        'threading',
        'logging',
        'pathlib',
        'webbrowser',
    ],
    hookspath=[],
    runtime_hooks=[],
    excludes=[
        # Exclude large packages not used by this app
        'tkinter',
        'matplotlib',
        'numpy',
        'scipy',
        'pandas',
        'PIL',
        'cv2',
        'pytest',
        'setuptools',
        'pip',
        '_pytest',
        'doctest',
        'pydoc',
        'unittest',
    ],
    noarchive=False,
    cipher=block_cipher,
)

pyz = PYZ(a.pure, a.zipped_data, cipher=block_cipher)

exe = EXE(
    pyz,
    a.scripts,
    [],
    exclude_binaries=True,
    name='KrakenSDR-Triangulator',
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=True,
    # Console window stays visible so operators can see server logs,
    # UDP status, and MAVLink connection state during field operations.
    console=True,
    icon=os.path.join(BASE, 'app', 'favicon.ico') if os.path.exists(os.path.join(BASE, 'app', 'favicon.ico')) else None,
)

coll = COLLECT(
    exe,
    a.binaries,
    a.datas,
    strip=False,
    upx=True,
    upx_exclude=[],
    name='KrakenSDR-Triangulator',
)
