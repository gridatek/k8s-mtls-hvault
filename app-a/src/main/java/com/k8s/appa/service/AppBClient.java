package com.k8s.appa.service;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import org.springframework.web.client.RestTemplate;

import java.util.Map;

@Service
public class AppBClient {

    private static final Logger logger = LoggerFactory.getLogger(AppBClient.class);

    private final RestTemplate restTemplate;
    private final String appBUrl;

    public AppBClient(RestTemplate restTemplate,
                      @Value("${app.b.url:https://app-b.default.svc.cluster.local:8443}") String appBUrl) {
        this.restTemplate = restTemplate;
        this.appBUrl = appBUrl;
    }

    public String callAppB() {
        try {
            logger.info("Calling App B at: {}/api/greet", appBUrl);
            Map<String, String> response = restTemplate.getForObject(
                    appBUrl + "/api/greet",
                    Map.class
            );
            String message = response != null ? response.get("message") : "No response";
            logger.info("Received response from App B: {}", message);
            return message;
        } catch (Exception e) {
            logger.error("Error calling App B", e);
            return "Error calling App B: " + e.getMessage();
        }
    }
}
