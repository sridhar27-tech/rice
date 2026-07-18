import { useState, useEffect, useRef } from "react";
import { invoke } from "@tauri-apps/api/core";
import { listen } from "@tauri-apps/api/event";
import { 
  Fan, 
  Cpu, 
  Tv, 
  Sliders, 
  TrendingUp, 
  Activity, 
  RefreshCw, 
  ShieldAlert, 
  Save,
  Moon
} from "lucide-react";
import { LineChart, Line, XAxis, YAxis, ResponsiveContainer, Tooltip } from "recharts";
import "./App.css";

interface CurvePoint {
  t: number; // temp
  s: number; // speed (0-255)
}

interface TelemetryData {
  mode: {
    mode: "auto" | "manual" | "curve";
    speed?: number;
    curve?: CurvePoint[];
  };
  current_speed_pct: number;
  cpu_fan_rpm: number;
  gpu_fan_rpm: number;
  cpu_temp: number;
  gpu_temp: number;
  watchdog_seconds: number;
}

const DEFAULT_CURVE: CurvePoint[] = [
  { t: 40, s: 40 },   // 40C -> 15%
  { t: 55, s: 100 },  // 55C -> 39%
  { t: 70, s: 160 },  // 70C -> 62%
  { t: 80, s: 210 },  // 80C -> 82%
  { t: 90, s: 255 },  // 90C -> 100%
];

function App() {
  const [isConnected, setIsConnected] = useState(false);
  const [telemetry, setTelemetry] = useState<TelemetryData | null>(null);
  
  // Local control states (for manual inputs)
  const [sliderSpeed, setSliderSpeed] = useState(50); // pct (0-100)
  const [curvePoints, setCurvePoints] = useState<CurvePoint[]>(DEFAULT_CURVE);
  
  // Rolling temp history for the chart
  const [tempHistory, setTempHistory] = useState<any[]>([]);
  
  const lastMsgTime = useRef<number>(0);
  const sliderDebounceTimer = useRef<any>(null);

  // Set up connection watchdog
  useEffect(() => {
    const checkConnection = setInterval(() => {
      const now = Date.now();
      if (now - lastMsgTime.current > 3000) {
        setIsConnected(false);
      }
    }, 1000);

    return () => clearInterval(checkConnection);
  }, []);

  // Listen to telemetry events from Tauri Rust backend
  useEffect(() => {
    const unlistenPromise = listen<string>("telemetry", (event) => {
      try {
        const rawJson = event.payload;
        const data: TelemetryData = JSON.parse(rawJson);
        setTelemetry(data);
        setIsConnected(true);
        lastMsgTime.current = Date.now();

        // Add to temp history
        setTempHistory((prev) => {
          const newHistory = [
            ...prev,
            {
              time: new Date().toLocaleTimeString([], { hour: '2-digit', minute: '2-digit', second: '2-digit' }),
              CPU: data.cpu_temp,
              GPU: data.gpu_temp,
            }
          ];
          // Keep last 30 readings
          if (newHistory.length > 30) {
            return newHistory.slice(newHistory.length - 30);
          }
          return newHistory;
        });

        // Sync local states if not currently editing/dragging
        if (data.mode.mode === "manual" && data.mode.speed !== undefined) {
          // If we are not actively dragging, sync manual slider
          // to make it consistent with the backend state
        }
      } catch (err) {
        console.error("Failed to parse telemetry:", err);
      }
    });

    return () => {
      unlistenPromise.then((unlisten) => unlisten());
    };
  }, []);

  // Spawn periodic heartbeat
  useEffect(() => {
    const heartbeatInterval = setInterval(() => {
      if (isConnected) {
        sendDaemonCommand({ cmd: "heartbeat" });
      }
    }, 4000);

    return () => clearInterval(heartbeatInterval);
  }, [isConnected]);

  const sendDaemonCommand = async (command: any) => {
    try {
      await invoke("send_command", { cmd: JSON.stringify(command) });
    } catch (err) {
      console.error("Failed to send command to daemon:", err);
      setIsConnected(false);
    }
  };

  const handleModeChange = (mode: "auto" | "manual" | "curve") => {
    if (mode === "auto") {
      sendDaemonCommand({ cmd: "set_auto" });
    } else if (mode === "manual") {
      const rawSpeed = Math.round((sliderSpeed * 255) / 100);
      sendDaemonCommand({ cmd: "set_manual", speed: rawSpeed });
    } else if (mode === "curve") {
      sendDaemonCommand({ cmd: "set_curve", curve: curvePoints });
    }
  };

  const handleSliderChange = (val: number) => {
    setSliderSpeed(val);
    
    // Debounce the socket write for manual slider
    if (sliderDebounceTimer.current) {
      clearTimeout(sliderDebounceTimer.current);
    }
    sliderDebounceTimer.current = setTimeout(() => {
      const rawSpeed = Math.round((val * 255) / 100);
      sendDaemonCommand({ cmd: "set_manual", speed: rawSpeed });
    }, 150);
  };

  const handleCurvePointChange = (index: number, field: "t" | "s", value: number) => {
    const newPoints = [...curvePoints];
    newPoints[index] = {
      ...newPoints[index],
      [field]: value
    };
    // Ensure temperatures remain sorted
    if (field === "t") {
      newPoints.sort((a, b) => a.t - b.t);
    }
    setCurvePoints(newPoints);
  };

  const applyCurve = () => {
    sendDaemonCommand({ cmd: "set_curve", curve: curvePoints });
  };

  const activeMode = telemetry?.mode?.mode || "auto";

  return (
    <div className="app-container">
      {/* Sidebar / Header */}
      <header className="app-header">
        <div className="header-brand">
          <Moon className="brand-icon" />
          <h1>Lightning Fan</h1>
        </div>
        <div className={`status-badge ${isConnected ? "connected" : "disconnected"}`}>
          <span className="dot"></span>
          {isConnected ? "Daemon Online" : "Daemon Offline"}
        </div>
      </header>

      {/* Main Grid Layout */}
      <main className="app-grid">
        {/* Telemetry Section */}
        <section className="card stats-card">
          <div className="card-header">
            <Activity className="section-icon" />
            <h2>Live Telemetry</h2>
          </div>
          
          <div className="metrics-grid">
            <div className="metric-item">
              <div className="metric-icon cpu-color">
                <Cpu size={24} />
              </div>
              <div className="metric-info">
                <span className="label">CPU Temp</span>
                <span className="value">{telemetry ? `${telemetry.cpu_temp}°C` : "N/A"}</span>
              </div>
            </div>

            <div className="metric-item">
              <div className="metric-icon gpu-color">
                <Tv size={24} />
              </div>
              <div className="metric-info">
                <span className="label">GPU Temp</span>
                <span className="value">{telemetry ? `${telemetry.gpu_temp}°C` : "N/A"}</span>
              </div>
            </div>

            <div className="metric-item">
              <div className="metric-icon fan-color">
                <Fan className={telemetry && telemetry.cpu_fan_rpm > 0 ? "spinning" : ""} size={24} />
              </div>
              <div className="metric-info">
                <span className="label">CPU Fan</span>
                <span className="value">{telemetry ? `${telemetry.cpu_fan_rpm} RPM` : "N/A"}</span>
              </div>
            </div>

            <div className="metric-item">
              <div className="metric-icon fan-color">
                <Fan className={telemetry && telemetry.gpu_fan_rpm > 0 ? "spinning" : ""} size={24} />
              </div>
              <div className="metric-info">
                <span className="label">GPU Fan</span>
                <span className="value">{telemetry ? `${telemetry.gpu_fan_rpm} RPM` : "N/A"}</span>
              </div>
            </div>
          </div>

          {/* Temperature Graph */}
          <div className="graph-container">
            <ResponsiveContainer width="100%" height={160}>
              <LineChart data={tempHistory}>
                <XAxis dataKey="time" hide />
                <YAxis domain={[30, 95]} width={25} stroke="#908caa" />
                <Tooltip 
                  contentStyle={{ backgroundColor: "#2a273f", border: "1px solid #393552", borderRadius: "8px" }}
                  labelStyle={{ color: "#e0def4" }}
                />
                <Line type="monotone" dataKey="CPU" stroke="#eb6f92" strokeWidth={2} dot={false} isAnimationActive={false} />
                <Line type="monotone" dataKey="GPU" stroke="#c4a7e7" strokeWidth={2} dot={false} isAnimationActive={false} />
              </LineChart>
            </ResponsiveContainer>
            <div className="graph-legend">
              <span className="legend-item"><span className="legend-dot cpu-bg"></span> CPU Temp</span>
              <span className="legend-item"><span className="legend-dot gpu-bg"></span> GPU Temp</span>
            </div>
          </div>
        </section>

        {/* Control Section */}
        <section className="card control-card">
          <div className="card-header">
            <Sliders className="section-icon" />
            <h2>Fan Mode Controls</h2>
          </div>

          {/* Mode Toggles */}
          <div className="mode-toggle-group">
            <button 
              className={`mode-btn ${activeMode === "auto" ? "active" : ""}`}
              onClick={() => handleModeChange("auto")}
              disabled={!isConnected}
            >
              <RefreshCw size={16} />
              <span>BIOS Auto</span>
            </button>
            <button 
              className={`mode-btn ${activeMode === "manual" ? "active" : ""}`}
              onClick={() => handleModeChange("manual")}
              disabled={!isConnected}
            >
              <Sliders size={16} />
              <span>Manual Slider</span>
            </button>
            <button 
              className={`mode-btn ${activeMode === "curve" ? "active" : ""}`}
              onClick={() => handleModeChange("curve")}
              disabled={!isConnected}
            >
              <TrendingUp size={16} />
              <span>Fan Curves</span>
            </button>
          </div>

          <div className="control-workspace">
            {activeMode === "auto" && (
              <div className="auto-info">
                <div className="info-icon">
                  <Moon size={48} className="pulse" />
                </div>
                <h3>Firmware Auto Mode</h3>
                <p>The laptop's BIOS/EC is automatically managing the fan speed curves based on internal thermal profiles.</p>
              </div>
            )}

            {activeMode === "manual" && (
              <div className="manual-controls">
                <h3>Manual Speed Target</h3>
                <div className="slider-container">
                  <div className="slider-header">
                    <span>Target Duty Cycle</span>
                    <span className="slider-value">{sliderSpeed}%</span>
                  </div>
                  <input 
                    type="range" 
                    min="5" 
                    max="100" 
                    value={sliderSpeed} 
                    onChange={(e) => handleSliderChange(parseInt(e.target.value))}
                    className="speed-range-slider"
                  />
                  <div className="slider-footer">
                    <span>Silent (5%)</span>
                    <span>Max Speed (100%)</span>
                  </div>
                </div>

                {telemetry && telemetry.watchdog_seconds > 0 && (
                  <div className="watchdog-alert">
                    <ShieldAlert size={16} />
                    <span>Watchdog active: Restoring auto in {telemetry.watchdog_seconds}s if UI disconnects.</span>
                  </div>
                )}
              </div>
            )}

            {activeMode === "curve" && (
              <div className="curve-editor">
                <div className="editor-header">
                  <h3>Edit Custom Fan Curve</h3>
                  <button className="save-btn" onClick={applyCurve}>
                    <Save size={16} />
                    <span>Apply Curve</span>
                  </button>
                </div>

                <div className="points-table">
                  <div className="table-header">
                    <span>Temp threshold (°C)</span>
                    <span>Fan duty cycle (%)</span>
                  </div>
                  
                  {curvePoints.map((point, index) => (
                    <div key={index} className="table-row">
                      <div className="input-group">
                        <input 
                          type="number" 
                          min="30" 
                          max="95" 
                          value={point.t}
                          onChange={(e) => handleCurvePointChange(index, "t", parseInt(e.target.value) || 0)}
                        />
                        <span className="unit">°C</span>
                      </div>
                      
                      <div className="input-group flex-grow">
                        <input 
                          type="range" 
                          min="12" 
                          max="255" 
                          value={point.s}
                          onChange={(e) => handleCurvePointChange(index, "s", parseInt(e.target.value) || 0)}
                          className="curve-row-slider"
                        />
                        <span className="unit-pct">{Math.round((point.s * 100) / 255)}%</span>
                      </div>
                    </div>
                  ))}
                </div>
              </div>
            )}
          </div>
        </section>
      </main>
    </div>
  );
}

export default App;
