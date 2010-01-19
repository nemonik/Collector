package org.mitre.honeyclient;

import java.io.File;
import java.util.HashMap;
import java.util.Map;

import org.apache.commons.io.FilenameUtils;
import org.artofsolving.jodconverter.document.DefaultDocumentFormatRegistry;
import org.artofsolving.jodconverter.document.DocumentFormat;
import org.artofsolving.jodconverter.document.DocumentFormatRegistry;
import org.artofsolving.jodconverter.office.OfficeException;
import org.artofsolving.jodconverter.office.OfficeManager;

import java.util.logging.Level;
import java.util.logging.Logger;
import org.artofsolving.jodconverter.StandardConversionTask;

/**
 *
 * @author    Michael Joseph Walsh (mailto:mjwalsh_n_o__s_p_a_m@mitre.org)
 * Copyright:: Copyright (c) 2010 The MITRE Corporation.  All Rights Reserved.
 * License:: GNU GENERAL PUBLIC LICENSE
 */
public class InsistOfficeDocumentConverter {

    private final OfficeManager officeManager;
    private final DocumentFormatRegistry formatRegistry;
    private Map<String, ?> defaultLoadProperties = createDefaultLoadProperties();

    public InsistOfficeDocumentConverter(OfficeManager officeManager) {
        this(officeManager, new DefaultDocumentFormatRegistry());
    }

    public InsistOfficeDocumentConverter(OfficeManager officeManager, DocumentFormatRegistry formatRegistry) {
        this.officeManager = officeManager;
        this.formatRegistry = formatRegistry;
    }

    private Map<String, Object> createDefaultLoadProperties() {
        Map<String, Object> loadProperties = new HashMap<String, Object>();
        loadProperties.put("Hidden", true);
        loadProperties.put("ReadOnly", true);
        return loadProperties;
    }

    public void setDefaultLoadProperties(Map<String, ?> defaultLoadProperties) {
        this.defaultLoadProperties = defaultLoadProperties;
    }

    public DocumentFormatRegistry getFormatRegistry() {
        return formatRegistry;
    }

    public void convert(File inputFile, File outputFile) throws OfficeException, InterruptedException {
        String outputExtension = FilenameUtils.getExtension(outputFile.getName());
        DocumentFormat outputFormat = formatRegistry.getFormatByExtension(outputExtension);
        convert(inputFile, outputFile, outputFormat);
    }

    public void convert(File inputFile, File outputFile, DocumentFormat outputFormat) throws OfficeException, InterruptedException {
        String inputExtension = FilenameUtils.getExtension(inputFile.getName());
        DocumentFormat inputFormat = formatRegistry.getFormatByExtension(inputExtension);
        StandardConversionTask conversionTask = new StandardConversionTask(inputFile, outputFile, outputFormat);
        conversionTask.setDefaultLoadProperties(defaultLoadProperties);
        conversionTask.setInputFormat(inputFormat);

        boolean notDone = true;

        while (notDone) {
            try {
                Logger.getLogger(InsistOfficeDocumentConverter.class.getName()).log(Level.INFO, "handling conversion task for " + Thread.currentThread().getName() + "...");
                officeManager.execute(conversionTask);
                Logger.getLogger(InsistOfficeDocumentConverter.class.getName()).log(Level.INFO, "handled conversion task for " + Thread.currentThread().getName() + "...");
                notDone = false;
            } catch (OfficeException e) {
                Logger.getLogger(InsistOfficeDocumentConverter.class.getName()).log(Level.SEVERE, e.toString());
            }
        }
    }
}
