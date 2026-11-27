//! Direct Discord RPC over the application's local IPC socket.
//! No Discord SDK or third-party IPC crate is used.

use godot::prelude::*;
use std::io::{Read, Write};
use std::sync::Mutex;

#[cfg(unix)]
use std::os::unix::net::UnixStream;

#[cfg(windows)]
use std::fs::OpenOptions;

enum IpcStream {
    #[cfg(unix)]
    Unix(UnixStream),
    #[cfg(windows)]
    Pipe(std::fs::File),
}

impl IpcStream {
    fn write_all(&mut self, bytes: &[u8]) -> bool {
        match self {
            #[cfg(unix)]
            IpcStream::Unix(s) => s.write_all(bytes).is_ok(),
            #[cfg(windows)]
            IpcStream::Pipe(s) => s.write_all(bytes).is_ok(),
        }
    }

    fn read_exact(&mut self, bytes: &mut [u8]) -> bool {
        match self {
            #[cfg(unix)]
            IpcStream::Unix(s) => s.read_exact(bytes).is_ok(),
            #[cfg(windows)]
            IpcStream::Pipe(s) => s.read_exact(bytes).is_ok(),
        }
    }
}

#[derive(Default)]
struct DiscordIpc {
    stream: Option<IpcStream>,
    nonce: u64,
    last_check: Option<std::time::Instant>,
    state_key: String,
    start: u64,
}

impl DiscordIpc {
    fn update_presence(
        &mut self,
        app_id: &str,
        mission: &str,
        selected: &str,
        in_hangar: bool,
    ) -> bool {
        let now = std::time::Instant::now();
        if let Some(last) = self.last_check {
            if now.duration_since(last).as_secs_f32() < 5.0 {
                return true;
            }
        }
        self.last_check = Some(now);

        if self.stream.is_none() && !self.connect(app_id) {
            return false;
        }
        let details = if in_hangar {
            "In the menu".to_string()
        } else {
            match mission {
                "takeoff" => "Runway Operations",
                "landing" => "Approach",
                "ramp" => "Ramp",
                "free" => "Free Flight",
                "patrol" => "Patrol",
                "conquest" => "Conquest",
                "rush" => "Rush",
                "warlords" => "Warlords",
                "tdm" => "Team Deathmatch",
                "ffa" => "Free For All",
                "cqb" => "Street Fight",
                "ground" => "Ground Combat",
                "arms" => "Combined Arms",
                "range" => "Firing Range",
                "carrier" => "Carrier Trap",
                "launch" => "Orbital Launch",
                "moon" => "Lunar Mission",
                "strike" => "Strike",
                "sandbox" => "Sandbox",
                other => other,
            }.to_string()
        };
        let mut state = "Combined Arms".to_string();
        // The game says what you are doing in its own words when it can: "@"
        // and then the line itself -- on foot, driving, sailing or flying, by
        // name. A bare id is still taken as an aeroplane, as it always was.
        if let Some(said) = selected.strip_prefix('@') {
            state = said.to_string();
        } else if selected == "foot" {
            state = "On foot".to_string();
        } else if !selected.is_empty() {
            let cleaned = selected.replace(':', " ");
            state = format!("Flying {}", title_words(&cleaned));
        }
        let key = format!("{}|{}", details, state);
        if key == self.state_key {
            return true;
        }
        if self.start == 0 {
            self.start = std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .map(|t| t.as_secs())
                .unwrap_or(0);
        }
        if self.set_activity(&details, &state, self.start) {
            self.state_key = key;
            true
        } else {
            false
        }
    }

    fn connect(&mut self, app_id: &str) -> bool {
        if self.stream.is_some() {
            return true;
        }
        let Some(stream) = open_ipc() else {
            return false;
        };
        self.stream = Some(stream);
        let pid = std::process::id();
        let hand = format!(
            "{{\"v\":1,\"client_id\":\"{}\"}}",
            json_escape(app_id)
        );
        if !send_frame(self.stream.as_mut().unwrap(), 0, hand.as_bytes()) {
            self.stream = None;
            return false;
        }
        let mut head = [0u8; 8];
        let handshake_ok = match self.stream.as_mut() {
            Some(stream) => stream.read_exact(&mut head),
            None => false,
        };
        if !handshake_ok {
            self.stream = None;
            return false;
        }
        let pid_text = pid.to_string();
        let envelope = format!(
            "{{\"cmd\":\"SET_ACTIVITY\",\"args\":{{\"pid\":{},\"activity\":{{\"details\":\"In the hangar\",\"state\":\"Combined Arms\",\"timestamps\":{{\"start\":{}}}}}}},\"nonce\":\"{}\"}}",
            pid_text,
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .map(|t| t.as_secs())
                .unwrap_or(0),
            &pid_text
        );
        let _ = send_frame(self.stream.as_mut().unwrap(), 1, envelope.as_bytes());
        true
    }

    fn set_activity(&mut self, details: &str, state: &str, start: u64) -> bool {
        let Some(stream) = self.stream.as_mut() else {
            return false;
        };
        self.nonce += 1;
        let pid = std::process::id();
        let body = format!(
            "{{\"cmd\":\"SET_ACTIVITY\",\"args\":{{\"pid\":{},\"activity\":{{\"details\":\"{}\",\"state\":\"{}\",\"timestamps\":{{\"start\":{}}}}}}},\"nonce\":\"discord-{}\"}}",
            pid,
            json_escape(details),
            json_escape(state),
            start,
            self.nonce
        );
        if !send_frame(stream, 1, body.as_bytes()) {
            self.stream = None;
            return false;
        }
        true
    }

    fn close(&mut self) {
        self.stream = None;
    }
}

fn open_ipc() -> Option<IpcStream> {
    #[cfg(unix)]
    {
        let mut paths = Vec::new();
        if let Ok(dir) = std::env::var("XDG_RUNTIME_DIR") {
            paths.push(format!("{}/discord-ipc-0", dir));
        }
        if let Ok(dir) = std::env::var("TMPDIR") {
            paths.push(format!("{}/discord-ipc-0", dir));
        }
        if let Ok(home) = std::env::var("HOME") {
            paths.push(format!("{}/.config/discord/discord-ipc-0", home));
        }
        for path in paths {
            if let Ok(s) = UnixStream::connect(path) {
                let _ = s.set_read_timeout(Some(std::time::Duration::from_millis(500)));
                let _ = s.set_write_timeout(Some(std::time::Duration::from_millis(500)));
                return Some(IpcStream::Unix(s));
            }
        }
    }

    #[cfg(windows)]
    {
        for i in 0..10 {
            let pipe = format!(r"\\.\pipe\discord-ipc-{}", i);
            if let Ok(f) = OpenOptions::new()
                .read(true)
                .write(true)
                .open(&pipe)
            {
                return Some(IpcStream::Pipe(f));
            }
        }
    }
    None
}

fn send_frame(stream: &mut IpcStream, opcode: u32, body: &[u8]) -> bool {
    let mut packet = Vec::with_capacity(8 + body.len());
    packet.extend_from_slice(&opcode.to_le_bytes());
    packet.extend_from_slice(&(body.len() as u32).to_le_bytes());
    packet.extend_from_slice(body);
    stream.write_all(&packet)
}

fn title_words(s: &str) -> String {
    s.split_whitespace()
        .map(|word| {
            let mut chars = word.chars();
            match chars.next() {
                Some(first) => {
                    let mut out = first.to_uppercase().to_string();
                    out.extend(chars);
                    out
                }
                None => String::new(),
            }
        })
        .collect::<Vec<_>>()
        .join(" ")
}

fn json_escape(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    for c in s.chars() {
        match c {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            c if c.is_control() => {
                out.push_str(&format!("\\u{:04x}", c as u32));
            }
            c => out.push(c),
        }
    }
    out
}

static IPC: Mutex<DiscordIpc> = Mutex::new(DiscordIpc {
    stream: None,
    nonce: 0,
    last_check: None,
    state_key: String::new(),
    start: 0,
});

#[derive(GodotClass)]
#[class(base=RefCounted, init)]
struct DiscordPresence {
    base: Base<RefCounted>,
}

#[godot_api]
impl DiscordPresence {
    #[func]
    fn update_presence(
        &self,
        app_id: GString,
        mission: GString,
        selected: GString,
        in_hangar: bool,
    ) -> bool {
        IPC.lock().unwrap().update_presence(
            app_id.to_string().as_str(),
            mission.to_string().as_str(),
            selected.to_string().as_str(),
            in_hangar,
        )
    }

    #[func]
    fn shutdown_native(&self) {
        IPC.lock().unwrap().close();
    }
}
