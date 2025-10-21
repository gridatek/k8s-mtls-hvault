package com.k8s.appb;

import org.apache.http.conn.ssl.SSLConnectionSocketFactory;
import org.apache.http.impl.client.CloseableHttpClient;
import org.apache.http.impl.client.HttpClients;
import org.apache.http.ssl.SSLContextBuilder;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.boot.web.client.RestTemplateBuilder;
import org.springframework.context.annotation.Bean;
import org.springframework.core.io.Resource;
import org.springframework.http.client.HttpComponentsClientHttpRequestFactory;
import org.springframework.web.client.RestTemplate;

import javax.net.ssl.SSLContext;

@SpringBootApplication
public class AppBApplication {

    public static void main(String[] args) {
        SpringApplication.run(AppBApplication.class, args);
    }

    @Bean
    public RestTemplate restTemplate(
            RestTemplateBuilder builder,
            @Value("${server.ssl.key-store}") Resource keyStore,
            @Value("${server.ssl.key-store-password}") String keyStorePassword,
            @Value("${server.ssl.trust-store}") Resource trustStore,
            @Value("${server.ssl.trust-store-password}") String trustStorePassword) throws Exception {

        SSLContext sslContext = SSLContextBuilder.create()
                .loadKeyMaterial(keyStore.getURL(), keyStorePassword.toCharArray(), keyStorePassword.toCharArray())
                .loadTrustMaterial(trustStore.getURL(), trustStorePassword.toCharArray())
                .build();

        SSLConnectionSocketFactory sslSocketFactory = new SSLConnectionSocketFactory(sslContext);

        CloseableHttpClient httpClient = HttpClients.custom()
                .setSSLSocketFactory(sslSocketFactory)
                .build();

        HttpComponentsClientHttpRequestFactory requestFactory = new HttpComponentsClientHttpRequestFactory(httpClient);

        return builder.requestFactory(() -> requestFactory).build();
    }
}
