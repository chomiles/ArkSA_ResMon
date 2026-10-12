using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Imaging;
using System.IO;
using System.Management.Automation;
using System.Management.Automation.Runspaces;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using System.Threading;
using System.Web.Script.Serialization;
using System.Windows.Forms;

[assembly: AssemblyTitle("ARK Resmon")]
[assembly: AssemblyDescription("ARK: Survival Ascended resource monitor")]
[assembly: AssemblyProduct("ARK Resmon")]
[assembly: AssemblyVersion("1.0.6.0")]
[assembly: AssemblyFileVersion("1.0.6.0")]

namespace ArkResmon
{
    public static class EmbeddedImages
    {
        private static readonly List<Stream> Streams = new List<Stream>();

        public static Image Load(string name)
        {
            Stream stream = Assembly.GetExecutingAssembly().GetManifestResourceStream("ArkResmon.Gifs." + name);
            if (stream == null) return null;
            try
            {
                Image image = Image.FromStream(stream);
                image.Tag = name;
                Streams.Add(stream); // GDI+ needs the stream for the lifetime of animated GIFs.
                return image;
            }
            catch { stream.Dispose(); throw; }
        }

        internal static void DisposeStreams()
        {
            foreach (Stream stream in Streams) stream.Dispose();
            Streams.Clear();
        }
    }

    internal sealed class Verification : IDisposable
    {
        [DllImport("kernel32.dll")]
        private static extern IntPtr GetConsoleWindow();
        private readonly System.Windows.Forms.Timer timer = new System.Windows.Forms.Timer();
        private readonly HashSet<string> frames = new HashSet<string>();
        private readonly string path;
        private readonly string gifName;
        private Image verificationImage;
        private readonly HashSet<string> expectedFrames = new HashSet<string>();
        private int ticks;
        internal bool Passed;
        private bool finished;

        internal Verification(string outputPath, string animationName = null)
        {
            path = Path.GetFullPath(outputPath);
            gifName = animationName;
            timer.Interval = 125;
            timer.Tick += Tick;
            timer.Start();
        }

        private static IEnumerable<Control> Controls(Control parent)
        {
            foreach (Control child in parent.Controls)
            {
                yield return child;
                foreach (Control nested in Controls(child)) yield return nested;
            }
        }

        private void Tick(object sender, EventArgs args)
        {
            if (Application.OpenForms.Count == 0) return;
            Form form = Application.OpenForms[0];
            if (form.Text != "ARK Resmon") return;
            try
            {
                ticks++;
                PictureBox avatar = null;
                List<string> labels = new List<string>();
                foreach (Control control in Controls(form))
                {
                    if (control is PictureBox && control.Width == 64 && control.Height == 64) avatar = (PictureBox)control;
                    if (control is Label) labels.Add(control.Text);
                }
                if (avatar == null || avatar.Image == null)
                {
                    if (ticks < 80) return; // Live monitoring paints its first sample after one second.
                    throw new InvalidOperationException("Character image missing");
                }
                if (gifName != null && verificationImage == null)
                {
                    verificationImage = EmbeddedImages.Load(gifName);
                    if (verificationImage == null) throw new InvalidOperationException("Unknown GIF: " + gifName);
                    using (Image reference = EmbeddedImages.Load(gifName))
                    {
                        for (int index = 0; index < reference.GetFrameCount(FrameDimension.Time); index++)
                        {
                            reference.SelectActiveFrame(FrameDimension.Time, index);
                            using (Bitmap expected = new Bitmap(64, 64))
                            using (Graphics graphics = Graphics.FromImage(expected))
                            {
                                graphics.Clear(avatar.BackColor);
                                graphics.DrawImageUnscaled(reference, 0, 0);
                                expectedFrames.Add(Hash(expected));
                            }
                        }
                    }
                    avatar.Image = verificationImage;
                    ticks = 0;
                }
                using (Bitmap bitmap = new Bitmap(64, 64))
                {
                    avatar.DrawToBitmap(bitmap, new Rectangle(0, 0, 64, 64));
                    string frameHash = Hash(bitmap);
                    if (gifName != null && !expectedFrames.Contains(frameHash)) throw new InvalidOperationException("Unexpected pixels or stale frame while rendering " + gifName);
                    frames.Add(frameHash);
                }
                if (ticks < 32) return;
                bool consoleAbsent = GetConsoleWindow() == IntPtr.Zero;
                bool noMeasurementError = !labels.Exists(delegate(string text) { return text.StartsWith("Measurement error:") || text.StartsWith("측정 오류") || text.StartsWith("測定エラー:"); });
                bool sampled = labels.Exists(delegate(string text) { return text == "ARK running" || text == "Waiting for ARK" || text.StartsWith("ARK 실행") || text == "ARK 実行中" || text == "ARK 起動待ち"; });
                Passed = consoleAbsent && noMeasurementError && sampled && frames.Count > 1;
                using (Bitmap full = new Bitmap(form.Width, form.Height))
                {
                    form.DrawToBitmap(full, new Rectangle(0, 0, full.Width, full.Height));
                    Point origin = form.PointToScreen(Point.Empty);
                    using (Bitmap client = full.Clone(new Rectangle(origin.X - form.Left, origin.Y - form.Top, form.ClientSize.Width, form.ClientSize.Height), full.PixelFormat))
                        client.Save(path + ".png", ImageFormat.Png);
                }
                Dictionary<string, object> report = new Dictionary<string, object>();
                report["passed"] = Passed;
                report["console_absent"] = consoleAbsent;
                report["animated_frame_changes"] = frames.Count;
                report["avatar"] = avatar.Image.Tag;
                if (gifName != null) report["all_rendered_frames_match_reference"] = true;
                report["labels"] = labels;
                Save(report);
                form.Close();
            }
            catch (Exception error) { Fail(error); form.Close(); }
        }

        internal void Fail(Exception error)
        {
            Passed = false;
            Dictionary<string, object> report = new Dictionary<string, object>();
            report["passed"] = false;
            report["error"] = error.ToString();
            Save(report);
        }

        private void Save(Dictionary<string, object> report)
        {
            finished = true;
            timer.Stop();
            File.WriteAllText(path, new JavaScriptSerializer().Serialize(report), new UTF8Encoding(false));
        }

        public void Dispose()
        {
            timer.Dispose();
            if (verificationImage != null) verificationImage.Dispose();
            if (!finished) Fail(new InvalidOperationException("Verification ended before measurements completed"));
        }

        private static string Hash(Bitmap bitmap)
        {
            using (MemoryStream stream = new MemoryStream())
            using (SHA256 sha = SHA256.Create())
            {
                bitmap.Save(stream, ImageFormat.Png);
                return BitConverter.ToString(sha.ComputeHash(stream.ToArray()));
            }
        }
    }

    internal static class Program
    {
        [STAThread]
        private static int Main(string[] args)
        {
            Verification verification = null;
            try
            {
                Application.EnableVisualStyles();
                Application.SetCompatibleTextRenderingDefault(false);
                bool simulateGpuFailure = args.Length == 2 && args[0] == "--verify-no-counters";
                if (args.Length == 3 && args[0] == "--verify-gif") verification = new Verification(args[2], args[1]);
                else if (args.Length == 2 && (args[0] == "--verify" || simulateGpuFailure)) verification = new Verification(args[1]);
                else if (args.Length != 0) throw new ArgumentException("Unknown command line option");

                string source;
                using (Stream stream = Assembly.GetExecutingAssembly().GetManifestResourceStream("ArkResmon.Runtime.ps1"))
                using (StreamReader reader = new StreamReader(stream, Encoding.UTF8, true))
                    source = reader.ReadToEnd();
                if (simulateGpuFailure)
                    source = source.Replace("    try { Initialize-Gpu } catch { $script:AdapterCounter = $null; $script:LastGpuInitError = $_.Exception.Message }", "    try { throw 'Simulated invalid counter index' } catch { $script:AdapterCounter = $null; $script:LastGpuInitError = $_.Exception.Message }");

                using (Runspace runspace = RunspaceFactory.CreateRunspace())
                {
                    runspace.ApartmentState = ApartmentState.STA;
                    runspace.ThreadOptions = PSThreadOptions.UseCurrentThread;
                    runspace.Open();
                    Runspace.DefaultRunspace = runspace;
                    using (PowerShell shell = PowerShell.Create())
                    {
                        shell.Runspace = runspace;
                        shell.AddScript(source).Invoke();
                        if (shell.HadErrors)
                        {
                            StringBuilder errors = new StringBuilder();
                            foreach (ErrorRecord error in shell.Streams.Error) errors.AppendLine(error.ToString());
                            throw new InvalidOperationException(errors.ToString());
                        }
                    }
                }
                return verification != null && !verification.Passed ? 1 : 0;
            }
            catch (Exception error)
            {
                if (verification != null) verification.Fail(error);
                else MessageBox.Show(error.Message, "ARK Resmon · Startup error", MessageBoxButtons.OK, MessageBoxIcon.Error);
                return 1;
            }
            finally
            {
                if (verification != null) verification.Dispose();
                EmbeddedImages.DisposeStreams();
            }
        }
    }
}
