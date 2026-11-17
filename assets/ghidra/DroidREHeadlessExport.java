// @category DroidRE
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardOpenOption;
import java.io.BufferedWriter;
import java.util.Base64;
import ghidra.app.util.headless.HeadlessScript;
import ghidra.app.decompiler.DecompInterface;
import ghidra.app.decompiler.DecompileResults;
import ghidra.program.model.listing.Function;

public class DroidREHeadlessExport extends HeadlessScript {
    private String field(String text, int limit) {
        if (text == null || text.isEmpty()) text = "(empty)";
        return Base64.getEncoder().encodeToString(text.substring(0,
            Math.min(text.length(), limit)).getBytes(StandardCharsets.UTF_8));
    }
    private void row(BufferedWriter out, String... values) throws Exception {
        out.write(String.join("\t", values));
        out.newLine();
    }
    @Override
    public void run() throws Exception {
        String[] args = getScriptArgs();
        if (args.length != 2 || currentProgram == null) {
            throw new IllegalArgumentException("Expected output and selector");
        }
        String selector = args[1];
        int functions = 0, previews = 0;
        boolean limited = false;
        DecompInterface engine = new DecompInterface();
        try (BufferedWriter out = Files.newBufferedWriter(Path.of(args[0]),
            StandardCharsets.UTF_8, StandardOpenOption.CREATE_NEW, StandardOpenOption.WRITE)) {
            row(out, "DROIDRE1", field(currentProgram.getLanguageID().toString(), 200));
            boolean ready = engine.openProgram(currentProgram);
            var iterator = currentProgram.getFunctionManager().getFunctions(true);
            while (iterator.hasNext() && functions < 256) {
                monitor.checkCancelled();
                Function f = iterator.next();
                String address = f.getEntryPoint().toString();
                row(out, "F", field(address, 128), field(f.getName(), 256));
                functions++;
                int calls = 0;
                for (Function target : f.getCalledFunctions(monitor)) {
                    monitor.checkCancelled();
                    if (calls++ >= 24) { limited = true; break; }
                    row(out, "C", field(address, 128),
                        field(target.getEntryPoint().toString(), 128), field(target.getName(), 256));
                }
                if (previews < 12 && (selector.equals("@first") ||
                    selector.equals(address) || selector.equals(f.getName()))) {
                    previews++;
                    String status = "unresolved", code = "Decompiler unavailable";
                    if (ready) {
                        DecompileResults result = engine.decompileFunction(f, 8, monitor);
                        monitor.checkCancelled();
                        if (result.decompileCompleted() && result.getDecompiledFunction() != null) {
                            code = result.getDecompiledFunction().getC();
                            status = code.length() > 12000 ? "clipped" : "observed";
                        } else { code = result.getErrorMessage(); }
                    }
                    row(out, "P", field(address, 128), status, field(code, 12000));
                }
            }
            row(out, "END", Integer.toString(functions), Integer.toString(previews),
                limited || iterator.hasNext() ? "limited" : "sampled");
        } finally { engine.dispose(); }
    }
}
