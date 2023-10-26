#[cfg(test)]
#[macro_use]
extern crate lazy_static;

#[cfg(test)]
mod tests {
    use std::process::Command;
    use std::sync::Once;
    use std::thread;
    use std::time::Duration;
    // use clap_builder::Parser;
    use anyhow::{anyhow, Context, Result};
    use hex::ToHex;
    use lazy_static::lazy_static;
    use starknet::core::types::{FieldElement, TransactionReceipt};
    use starknet::providers::jsonrpc::JsonRpcResponse;
    use starknet::signers::SigningKey;

    use proptest::prelude::*;

    const KATANA_ENDPOINT: &str = "http://localhost:5050";
    const WORLD: &str = "0x223b959926c92e10a5de78a76871fa40cefafbdce789137843df7c7b30e3e0";

    lazy_static! {
        // load output from katana launched with `katana --accounts 255 > prefunded.txt`
        // this allows for up to 255 concurrent accounts without the need to fund them
        static ref PAIRS: Vec<(String, String)> = {
            // load from file
            let file_contents =
                std::fs::read_to_string("prefunded.txt").expect("Failed to read prefunded.txt");

            // parse just the hexadecimal values
            let hexes = file_contents
                .lines()
                .filter(|l| l.contains('|'))
                .map(|l| l.split('|').skip(2).next().unwrap().trim().to_owned())
                .collect::<Vec<_>>();

            // convert to pairs of address and private key
            hexes.chunks(3)
                .map(|chunk| (chunk[0].to_owned(), chunk[1].to_owned())) // Address, private key
                .collect::<Vec<_>>()
        };
    }

    fn paid_fee(tx: &str) -> Result<FieldElement> {
        let client = reqwest::blocking::Client::new();
        let body = format!(
            "{{\"jsonrpc\": \"2.0\",\"method\": \"starknet_getTransactionReceipt\",\"params\": [\"{}\"],\"id\": 1}}",
            tx,
        );

        let mut retries = 0;
        let receipt = loop {
            let res = client
                .post(KATANA_ENDPOINT)
                .body(body.clone())
                .header("Content-Type", "application/json")
                .send()
                .context("Failed to send request")?;

            if res.status() != 200 {
                return Err(anyhow!("Failed to fetch receipt"));
            }

            let receipt: JsonRpcResponse<TransactionReceipt> =
                res.json().context("Failed to parse response")?;

            match receipt {
                JsonRpcResponse::Success { result, .. } => break result,
                JsonRpcResponse::Error { error, .. } => {
                    if retries > 10 {
                        return Err(anyhow!("Transaction {} failed with: {}", tx, error));
                    } else {
                        retries += 1;
                    }
                }
            }

            thread::sleep(Duration::from_millis(50));
        };

        if let TransactionReceipt::Invoke(receipt) = receipt {
            Ok(receipt.actual_fee)
        } else {
            return Err(anyhow!("Not an invoke transaction"));
        }
    }

    fn execute(entrypoint: &str, calldata: Option<String>) -> String {
        let signer = SigningKey::from_random();
        let private = signer.secret_scalar().to_bytes_be().encode_hex::<String>();
        let address = signer.verifying_key().scalar().to_bytes_be().encode_hex::<String>();

        let private = String::from("0x") + &private;
        let address = String::from("0x") + &address;

        println!("Address: {}", address);
        println!("Private: {}", private);

        let mut args = vec![
            "execute",
            "--account-address",
            // "0x517ececd29116499f4a1b64b094da79ba08dfd54a3edaa316134c41f8160973",
            &address,
            "--private-key",
            // "0x1800000000300000180000000000030000000000003006001800006600",
            &private,
            "--rpc-url",
            "http://localhost:5050",
            "--world",
            WORLD,
            entrypoint,
        ];
        if let Some(ref calldata) = calldata {
            args.extend(["--calldata", calldata]);
        }

        // looks like it doesn't work at the moment, so using installed version of sozo
        // sozo::cli_main(SozoArgs::parse_from(args)).expect("Execution error");

        let output = Command::new("sozo").args(args).output().expect("failed to execute process");
        assert!(
            output.status.success(),
            "Execution failed at: {}",
            String::from_utf8(output.stderr).unwrap()
        );
        let tx = String::from_utf8(output.stdout)
            .expect("Failed to parse output")
            .strip_prefix("Transaction: ")
            .expect("Invalid output")
            .trim()
            .to_owned();
        assert_eq!(&tx[0..2], "0x", "Invalid tx hash");
        tx
    }

    #[test]
    fn prepare_test() {
        assert_eq!(PAIRS[0].0, "0x517ececd29116499f4a1b64b094da79ba08dfd54a3edaa316134c41f8160973");
    }

    // does not need proptest, as it doesn't use any input
    #[test]
    fn bench_spawn() {
        let tx = execute("spawn", None);

        let fee = paid_fee(&tx).unwrap();
        assert!(fee > FieldElement::ONE);
        println!("Tx: {}, fee: {}", tx, fee);
    }

    proptest! {
        #[test]
        fn bench_move(c in "0x[0-3]") {
            let tx = execute("move", Some(c.clone()));

            let fee = paid_fee(&tx).expect("Failed to fetch fee");
            assert!(fee > FieldElement::ONE);
            println!("Data: {} in tx: {}, with fee: {}", c, tx, fee);
        }
    }

    proptest! {
        #[test]
        fn bench_emit(s in "[A-Za-z0-9]{1,31}") {
            let s_hex = s.as_bytes().encode_hex::<String>();

            let tx = execute("bench_emit", Some("0x".to_owned() + &s_hex));

            let fee = paid_fee(&tx).expect("Failed to fetch fee");
            assert!(fee > FieldElement::ONE);
            println!("tx: {}\tfee: {}\tcalldata: {}", tx, fee, s);
        }
    }

    proptest! {
        #[test]
        fn bench_set(s in "[A-Za-z0-9]{1,31}") {
            let s_hex = s.as_bytes().encode_hex::<String>();

            let tx = execute("bench_set", Some("0x".to_owned() + &s_hex));

            let fee = paid_fee(&tx).expect("Failed to fetch fee");
            assert!(fee > FieldElement::ONE);
            println!("tx: {}\tfee: {}\tcalldata: {}", tx, fee, s);
        }
    }

    proptest! {
        #[test]
        fn bench_get(s in "[A-Za-z0-9]{1,31}") {
            let s_hex = s.as_bytes().encode_hex::<String>();

            execute("bench_set", Some("0x".to_owned() + &s_hex));
            let tx = execute("bench_get", None);

            let fee = paid_fee(&tx).expect("Failed to fetch fee");
            assert!(fee > FieldElement::ONE);
            println!("tx: {}\tfee: {}\tcalldata: {}", tx, fee, s);
        }
    }
}