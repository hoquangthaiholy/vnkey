pub mod convert_tool;
pub mod english_dictionary;
pub mod key_engine;
pub mod macro_engine;
pub mod programming_fsm;
pub mod vietnamese;
#[cfg(test)]
mod tests;

pub use convert_tool::{convert_text, CodeTable, ConvertOptions};
pub use english_dictionary::EnglishDictionary;
pub use key_engine::{InputLanguage, InputMethod, KeyEngine};
pub use macro_engine::MacroEngine;
pub use programming_fsm::ProgrammingFSM;
pub use vietnamese::VietnameseData;




