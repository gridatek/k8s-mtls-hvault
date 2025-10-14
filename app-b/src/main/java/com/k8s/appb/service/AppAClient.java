package com.k8s.appb.service;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import org.springframework.web.client.RestTemplate;

import java.util.Map;

@Service
public class AppAClient {

    private static final Logger logger = LoggerFactory.getLogger(AppAClient.class);

    private final RestTemplate restTemplate;
    private final String appAUrl;

    public AppAClient(RestTemplate restTemplate,
                      @Value("${app.a.url:https://app-a.default.svc.cluster.local:8443}") String appAUrl) {
        this.restTemplate = restTemplate;
        this.appAUrl = appAUrl;
    }

    public String callAppA() {
        try {
            logger.info("Calling App A at: {}/api/greet", appAUrl);
            Map<String, String> response = restTemplate.getForObject(
                    appAUrl + "/api/greet",
                    Map.class
            );
            String message = response != null ? response.get("message") : "No response";
            logger.info("Received response from App A: {}", message);
            return message;
        } catch (Exception e) {
            logger.error("Error calling App A", e);
            return "Error calling App A: " + e.getMessage();
        }
    }
}
