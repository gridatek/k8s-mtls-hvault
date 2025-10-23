package com.k8s.appa.service;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.context.event.ApplicationReadyEvent;
import org.springframework.context.event.EventListener;
import org.springframework.stereotype.Service;

import java.io.BufferedReader;
import java.io.InputStreamReader;

//@Service
public class CertificateInfoService {

    private static final Logger logger = LoggerFactory.getLogger(CertificateInfoService.class);

    @Value("${server.ssl.key-store}")
    private String keyStorePath;

    @Value("${server.ssl.key-store-password}")
    private String keyStorePassword;

    @Value("${server.ssl.trust-store}")
    private String trustStorePath;

    @Value("${server.ssl.trust-store-password}")
    private String trustStorePassword;

    @EventListener(ApplicationReadyEvent.class)
    public void logCertificateInfo() {
        logger.info("=".repeat(80));
        logger.info("CERTIFICATE INFORMATION (Using keytool commands)");
        logger.info("=".repeat(80));

        // Extract file paths from Spring Resource URLs
        String keystoreFile = extractFilePath(keyStorePath);
        String truststoreFile = extractFilePath(trustStorePath);

        logger.info("Keystore Path: {}", keystoreFile);
        logger.info("Truststore Path: {}", truststoreFile);
        logger.info("-".repeat(80));

        logKeystoreInfo(keystoreFile);
        logger.info("-".repeat(80));
        logTruststoreInfo(truststoreFile);

        logger.info("=".repeat(80));
    }

    private String extractFilePath(String path) {
        // Remove file:/ prefix if present
        if (path.startsWith("file:")) {
            path = path.substring(5);
        }
        // Handle Windows paths
        if (path.startsWith("/") && path.contains(":")) {
            path = path.substring(1);
        }
        return path;
    }

    private void logKeystoreInfo(String keystoreFile) {
        logger.info("KEYSTORE INFORMATION (PKCS12):");
        logger.info("");

        // List keystore entries
        logger.info(">>> Executing: keytool -list -keystore {} -storepass [REDACTED] -storetype PKCS12", keystoreFile);
        executeCommand(new String[]{
                "keytool", "-list",
                "-keystore", keystoreFile,
                "-storepass", keyStorePassword,
                "-storetype", "PKCS12"
        });

        logger.info("");
        logger.info(">>> Detailed certificate information:");
        logger.info(">>> Executing: keytool -list -v -keystore {} -storepass [REDACTED] -storetype PKCS12", keystoreFile);
        executeCommand(new String[]{
                "keytool", "-list", "-v",
                "-keystore", keystoreFile,
                "-storepass", keyStorePassword,
                "-storetype", "PKCS12"
        });
    }

    private void logTruststoreInfo(String truststoreFile) {
        logger.info("TRUSTSTORE INFORMATION (JKS):");
        logger.info("");

        // List truststore entries
        logger.info(">>> Executing: keytool -list -keystore {} -storepass [REDACTED] -storetype JKS", truststoreFile);
        executeCommand(new String[]{
                "keytool", "-list",
                "-keystore", truststoreFile,
                "-storepass", trustStorePassword,
                "-storetype", "JKS"
        });

        logger.info("");
        logger.info(">>> Detailed certificate information:");
        logger.info(">>> Executing: keytool -list -v -keystore {} -storepass [REDACTED] -storetype JKS", truststoreFile);
        executeCommand(new String[]{
                "keytool", "-list", "-v",
                "-keystore", truststoreFile,
                "-storepass", trustStorePassword,
                "-storetype", "JKS"
        });
    }

    private void executeCommand(String[] command) {
        try {
            ProcessBuilder processBuilder = new ProcessBuilder(command);
            processBuilder.redirectErrorStream(true);
            Process process = processBuilder.start();

            try (BufferedReader reader = new BufferedReader(new InputStreamReader(process.getInputStream()))) {
                String line;
                while ((line = reader.readLine()) != null) {
                    logger.info("  {}", line);
                }
            }

            int exitCode = process.waitFor();
            if (exitCode != 0) {
                logger.error("  Command exited with code: {}", exitCode);
            }

        } catch (Exception e) {
            logger.error("  ERROR executing command: {}", e.getMessage(), e);
        }
    }
}
