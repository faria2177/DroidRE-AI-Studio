import java.io.InputStream;
import java.nio.file.Files;
import java.nio.file.Path;
import java.security.CodeSigner;
import java.security.MessageDigest;
import java.security.cert.Certificate;
import java.util.HashSet;
import java.util.HexFormat;
import java.util.Locale;
import java.util.Set;
import java.util.jar.JarEntry;
import java.util.jar.JarFile;

/** Check every non-signature file in a signed AAB against one expected leaf certificate. */
public class VerifyBundleSigners {
    private static final long LIMIT = 2L * 1024 * 1024 * 1024;

    private static boolean signingMetadata(String name) {
        String upper = name.toUpperCase(Locale.ROOT);
        if (!upper.startsWith("META-INF/")) return false;
        String leaf = upper.substring(9);
        return !leaf.contains("/") && (leaf.equals("MANIFEST.MF") ||
                leaf.endsWith(".SF") || leaf.endsWith(".RSA") ||
                leaf.endsWith(".DSA") || leaf.endsWith(".EC") || leaf.startsWith("SIG-"));
    }

    public static void main(String[] args) throws Exception {
        if (args.length != 2 || !args[1].matches("[a-fA-F0-9]{64}")) {
            throw new IllegalArgumentException("Usage: VerifyBundleSigners.java bundle.aab EXPECTED_SHA256");
        }
        Path path = Path.of(args[0]);
        if (!Files.isRegularFile(path) || Files.size(path) > LIMIT) {
            throw new IllegalArgumentException("Bundle must be a regular file within 2 GiB");
        }
        String expected = args[1].toLowerCase(Locale.ROOT);
        Set<String> names = new HashSet<>();
        boolean config = false, manifest = false;
        long total = 0;
        int count = 0;
        byte[] buffer = new byte[65536];
        MessageDigest sha = MessageDigest.getInstance("SHA-256");
        try (JarFile jar = new JarFile(path.toFile(), true)) {
            var entries = jar.entries();
            while (entries.hasMoreElements()) {
                JarEntry entry = entries.nextElement();
                String name = entry.getName();
                if (names.size() >= 200000 || !names.add(name)) {
                    throw new SecurityException("Too many or duplicate entries");
                }
                if (entry.isDirectory() || signingMetadata(name)) continue;
                if (entry.getSize() < 0 || entry.getSize() > LIMIT - total) {
                    throw new SecurityException("Invalid or oversized bundle payload");
                }
                try (InputStream in = jar.getInputStream(entry)) {
                    int n;
                    while ((n = in.read(buffer)) != -1) {
                        total += n;
                        if (total > LIMIT) throw new SecurityException("Bundle payload limit exceeded");
                    }
                }
                CodeSigner[] signers = entry.getCodeSigners();
                if (signers == null || signers.length != 1) {
                    throw new SecurityException("Missing or multiple signers: " + name);
                }
                Certificate leaf = signers[0].getSignerCertPath().getCertificates().get(0);
                String actual = HexFormat.of().formatHex(sha.digest(leaf.getEncoded()));
                if (!expected.equals(actual)) throw new SecurityException("Unexpected leaf certificate: " + name);
                config |= name.equals("BundleConfig.pb");
                manifest |= name.equals("base/manifest/AndroidManifest.xml");
                count++;
            }
        }
        if (!config || !manifest) throw new SecurityException("Required AAB members missing");
        System.out.println("Verified " + count + " payload entries with expected signing certificate.");
    }
}
