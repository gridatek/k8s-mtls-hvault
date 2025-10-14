package com.k8s.appa.controller;

import com.k8s.appa.service.AppBClient;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.HashMap;
import java.util.Map;

@RestController
@RequestMapping("/api")
public class CommunicationController {

    private final AppBClient appBClient;

    public CommunicationController(AppBClient appBClient) {
        this.appBClient = appBClient;
    }

    @GetMapping("/call-app-b")
    public Map<String, String> callAppB() {
        String responseFromB = appBClient.callAppB();
        Map<String, String> response = new HashMap<>();
        response.put("from", "app-a");
        response.put("app-b-response", responseFromB);
        return response;
    }
}
