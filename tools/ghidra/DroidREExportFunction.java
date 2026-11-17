// Export the selected function's pseudocode and static calls for local review.
// @category DroidRE
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.StandardOpenOption;
import java.io.File;
import ghidra.app.script.GhidraScript;
import ghidra.app.decompiler.DecompInterface;
import ghidra.app.decompiler.DecompileResults;
import ghidra.program.model.listing.Function;

public class DroidREExportFunction extends GhidraScript {
    @Override
    public void run() throws Exception {
        if (currentProgram == null || currentAddress == null) {
            printerr("Open an analyzed program and select a function first.");
            return;
        }
        Function f = currentProgram.getFunctionManager().getFunctionContaining(currentAddress);
        if (f == null) {
            printerr("No function at current address.");
            return;
        }
        File destination = askFile("New text evidence file (outside input project)", "Export");
        if (destination.exists()) {
            printerr("Choose a new path; existing files are never overwritten.");
            return;
        }
        DecompInterface engine = new DecompInterface();
        try {
            if (!engine.openProgram(currentProgram)) {
                printerr("Cannot initialize decompiler.");
                return;
            }
            DecompileResults result = engine.decompileFunction(f, 30, monitor);
            monitor.checkCancelled();
            StringBuilder out = new StringBuilder();
            out.append("Ghidra static function evidence; NOT original source\n");
            out.append("Function: ").append(f.getName()).append("\n");
            out.append("Entry: ").append(f.getEntryPoint()).append("\n");
            out.append("Language: ").append(currentProgram.getLanguageID()).append("\n");
            out.append("\nObserved called functions (not a complete runtime graph):\n");
            int n = 0;
            for (Function target : f.getCalledFunctions(monitor)) {
                monitor.checkCancelled();
                if (n++ >= 128) {
                    out.append("(call list clipped)\n");
                    break;
                }
                out.append(target.getEntryPoint()).append(" ").append(target.getName()).append("\n");
            }
            out.append("\nDecompiler output:\n");
            if (result.decompileCompleted() && result.getDecompiledFunction() != null) {
                String c = result.getDecompiledFunction().getC();
                out.append(c.substring(0, Math.min(c.length(), 60000)));
                if (c.length() > 60000) out.append("\n(output clipped)\n");
            } else {
                out.append("Unresolved: ").append(result.getErrorMessage()).append("\n");
            }
            Files.write(destination.toPath(), out.toString().getBytes(StandardCharsets.UTF_8),
                StandardOpenOption.CREATE_NEW, StandardOpenOption.WRITE);
            println("Exported selected function: " + destination);
        } finally {
            engine.dispose();
        }
    }
}
