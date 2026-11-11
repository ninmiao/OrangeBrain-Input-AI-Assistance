"""Generate a fresh certificate for the debug-only local HTTPS fixture."""
from pathlib import Path
import datetime,ipaddress
from cryptography import x509
from cryptography.x509.oid import NameOID
from cryptography.hazmat.primitives import hashes,serialization
from cryptography.hazmat.primitives.asymmetric import rsa
root=Path(__file__).resolve().parents[2]
(root/'.tools').mkdir(exist_ok=True)
key=rsa.generate_private_key(public_exponent=65537,key_size=2048)
name=x509.Name([x509.NameAttribute(NameOID.COMMON_NAME,'Zephyr Input local test only')])
now=datetime.datetime.now(datetime.timezone.utc)
cert=(x509.CertificateBuilder().subject_name(name).issuer_name(name).public_key(key.public_key()).serial_number(x509.random_serial_number())
    .not_valid_before(now-datetime.timedelta(days=1)).not_valid_after(now+datetime.timedelta(days=365))
    .add_extension(x509.SubjectAlternativeName([x509.IPAddress(ipaddress.ip_address('10.0.2.2')),x509.IPAddress(ipaddress.ip_address('127.0.0.1'))]),False)
    .add_extension(x509.BasicConstraints(ca=True,path_length=None),True).sign(key,hashes.SHA256()))
(root/'.tools/mock-key.pem').write_bytes(key.private_bytes(serialization.Encoding.PEM,serialization.PrivateFormat.PKCS8,serialization.NoEncryption()))
(root/'.tools/mock-cert.pem').write_bytes(cert.public_bytes(serialization.Encoding.PEM))
raw=root/'android/app/src/debug/res/raw';raw.mkdir(parents=True,exist_ok=True)
(raw/'ai_test_certificate.pem').write_bytes(cert.public_bytes(serialization.Encoding.PEM))
print('Certificate regenerated. Rebuild debug APK before running fixture tests.')
