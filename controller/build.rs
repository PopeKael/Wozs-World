fn main() {
    println!("cargo:rerun-if-changed=assets/world-dock.ico");

    if std::env::var("CARGO_CFG_TARGET_OS").as_deref() == Ok("windows") {
        let mut resources = winres::WindowsResource::new();
        resources
            .set_icon("assets/world-dock.ico")
            .set("FileDescription", "Woz's World Dock")
            .set("ProductName", "Woz's World Dock");
        resources
            .compile()
            .expect("could not embed the World Dock application icon");
    }
}
